Set-StrictMode -Version Latest

# =============================================================================
#  UI.Progress.ps1
#  Real-time progress display during assessment execution.
#  No fake percentages. Status only comes from real module results.
# =============================================================================

#region --- Progress state ---

function New-ADHCProgressState {
    <#
    .SYNOPSIS
        Creates an in-memory progress state used by the OnCategoryStart/End
        callbacks. Keeps the row layout stable across updates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Total,
        [string]$Domain,
        [string]$StartedAt
    )

    [PSCustomObject]@{
        PSTypeName = 'ADHC.ProgressState'
        Total      = $Total
        Done       = 0
        Domain     = $Domain
        StartedAt  = $StartedAt
        Rows       = [System.Collections.Generic.List[object]]::new()   # completed rows
        Current    = $null   # in-flight row
        RunSw      = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

function Get-ADHCStatusColor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Status)
    switch ($Status) {
        'PASS'    { return 'Success' }
        'INFO'    { return 'Info' }
        'WARNING' { return 'Warning' }
        'FAIL'    { return 'Danger' }
        'UNKNOWN' { return 'Muted' }
        'RUNNING' { return 'Primary' }
        'SKIPPED' { return 'Muted' }
        default   { return 'Accent' }
    }
}

#endregion

#region --- Rendering ---

function Write-ADHCRowLine {
    <#
    .SYNOPSIS
        Writes one line like:
          [03/11] DNS ................................ [ OK ]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status
    )

    $cPrimary  = Get-ADHCColor -Name 'Primary'
    $cMuted    = Get-ADHCColor -Name 'Muted'
    $statusCol = Get-ADHCColor -Name (Get-ADHCStatusColor -Status $Status)

    $idx = '[{0:D2}/{1:D2}]' -f $Index, $Total
    $tag = '[{0,-7}]' -f $Status

    # Compose the middle dotted line so total visible width is stable.
    $fixedLen = $idx.Length + 1 + $Name.Length + 1 + $tag.Length
    $fill = 70 - $fixedLen
    if ($fill -lt 3) { $fill = 3 }
    $dots = '.' * $fill

    Write-Host ('  {0} ' -f $idx) -ForegroundColor $cMuted -NoNewline
    Write-Host $Name -ForegroundColor $cPrimary -NoNewline
    Write-Host (' {0} ' -f $dots) -ForegroundColor $cMuted -NoNewline
    Write-Host $tag -ForegroundColor $statusCol
}

function Show-ADHCProgressHeader {
    [CmdletBinding()]
    param(
        [string]$Domain,
        [string]$StartedAt,
        [int]$Total
    )
    Write-Host ''
    Write-Host '  AD HEALTH CHECK TOOLKIT' -ForegroundColor (Get-ADHCColor -Name 'Primary')
    Write-Host ('  Execucao: {0}' -f $StartedAt) -ForegroundColor (Get-ADHCColor -Name 'Muted')
    if ($Domain) {
        Write-Host ('  Dominio:  {0}' -f $Domain) -ForegroundColor (Get-ADHCColor -Name 'Muted')
    }
    Write-Host ('  Auditorias: {0}' -f $Total) -ForegroundColor (Get-ADHCColor -Name 'Muted')
    Write-Host ''
}

function Show-ADHCProgressStart {
    <#
    .SYNOPSIS
        Called once before starting the assessment.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$State)

    Show-ADHCProgressHeader -Domain $State.Domain -StartedAt $State.StartedAt -Total $State.Total
}

function Show-ADHCProgressCategoryStart {
    <#
    .SYNOPSIS
        Called by the OnCategoryStart callback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$State,
        [Parameter(Mandatory)][hashtable]$Event
    )
    $State.Current = [PSCustomObject]@{
        Index  = [int]$Event.Index
        Total  = [int]$Event.Total
        Name   = [string]$Event.Name
    }
    Write-ADHCRowLine -Index $State.Current.Index -Total $State.Current.Total -Name $State.Current.Name -Status 'RUNNING'
}

function Show-ADHCProgressCategoryEnd {
    <#
    .SYNOPSIS
        Called by the OnCategoryEnd callback. Replaces the previous row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$State,
        [Parameter(Mandatory)][hashtable]$Event
    )

    $status = [string]$Event.Status
    $reason = ''
    if ($Event.ContainsKey('Reason') -and $Event.Reason) { $reason = [string]$Event.Reason }

    # Move cursor up one line and rewrite the row.
    try {
        $curTop = [Console]::CursorTop
        if ($curTop -gt 0) { [Console]::SetCursorPosition(0, $curTop - 1) }
    } catch { }

    $idx   = [int]$Event.Index
    $total = [int]$Event.Total
    $name  = [string]$Event.Name

    # Build a padded line so we overwrite the previous one completely.
    $cMuted   = Get-ADHCColor -Name 'Muted'
    $cPrimary = Get-ADHCColor -Name 'Primary'
    $statusCol= Get-ADHCColor -Name (Get-ADHCStatusColor -Status $status)

    $idxText = '[{0:D2}/{1:D2}]' -f $idx, $total
    $tagText = '[{0,-7}]' -f $status
    $fixed   = $idxText.Length + 1 + $name.Length + 1 + $tagText.Length
    $fill    = 70 - $fixed
    if ($fill -lt 3) { $fill = 3 }
    $dots    = '.' * $fill

    # Compose then pad to a fixed width to fully overwrite.
    $line = '  {0} {1} {2} {3}' -f $idxText, $name, $dots, $tagText
    if ($line.Length -lt 78) { $line = $line.PadRight(78) }

    # Print with colors: we have to split into colored segments again.
    Write-Host ('  {0} ' -f $idxText) -ForegroundColor $cMuted -NoNewline
    Write-Host $name -ForegroundColor $cPrimary -NoNewline
    Write-Host (' {0} ' -f $dots) -ForegroundColor $cMuted -NoNewline
    Write-Host $tagText -ForegroundColor $statusCol -NoNewline
    # Pad with spaces (muted) so the previous longer line is fully overwritten.
    $tailPad = 78 - ($idxText.Length + 1 + $name.Length + 1 + $dots.Length + 1 + $tagText.Length)
    if ($tailPad -gt 0) { Write-Host (' ' * $tailPad) -NoNewline }
    Write-Host ''

    if ($reason) {
        Write-Host ('           ^ {0}' -f $reason) -ForegroundColor $cMuted
    }

    $State.Done++
    $State.Rows.Add([PSCustomObject]@{
        Index  = $idx
        Total  = $total
        Name   = $name
        Status = $status
        Reason = $reason
    })
    $State.Current = $null
}

function Show-ADHCProgressDone {
    <#
    .SYNOPSIS
        Called after the assessment returns. Prints elapsed time.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$State)
    $State.RunSw.Stop()
    Write-Host ''
    Write-Host ('  Tempo total: {0:N1}s' -f $State.RunSw.Elapsed.TotalSeconds) -ForegroundColor (Get-ADHCColor -Name 'Muted')
    Write-Host ''
}

#endregion