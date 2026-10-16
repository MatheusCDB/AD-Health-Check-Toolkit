Set-StrictMode -Version Latest

# =============================================================================
#  UI.CheckSelection.ps1
#  Checkbox-style selection of audit categories.
#  Depends on UI.Console.ps1 and UI.Banner.ps1.
# =============================================================================

#region --- Catalog mapping ---

function Get-ADHCSelectableCategories {
    <#
    .SYNOPSIS
        Returns the ordered list of categories the user can select.
        Each entry has: Key (menu number), Name (as in CheckCatalog),
        Label (human friendly), EnabledByDefault, RequiresFlag.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$CheckCatalog)

    # Friendly, locale-neutral labels for the selection screen.
    $labels = @{
        'Discovery'          = 'Descoberta dos Domain Controllers'
        'Connectivity'       = 'Conectividade e portas'
        'Services'           = 'Servicos essenciais'
        'DNS'                = 'DNS'
        'Replication'        = 'Replicacao do Active Directory'
        'Topology'           = 'Topologia e Sites'
        'SysvolNetlogon'     = 'SYSVOL e NETLOGON'
        'FSMO'               = 'FSMO'
        'TimeSynchronization'= 'Sincronizacao de horario'
        'EventLogs'          = 'Eventos do Windows'
        'GroupPolicy'        = 'Politicas de Grupo'
        'DCDiag'             = 'Diagnosticos DCDiag'
    }

    $order = @(
        'Discovery','Services','Connectivity','DNS','Replication',
        'Topology','SysvolNetlogon','FSMO','TimeSynchronization',
        'EventLogs','GroupPolicy','DCDiag'
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $index = 1
    foreach ($name in $order) {
        $entry = $CheckCatalog.Categories | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $entry) { continue }

        $lbl = $name
        if ($labels.ContainsKey($name)) { $lbl = $labels[$name] }

        $result.Add([PSCustomObject]@{
            Key              = $index
            Name             = $name
            Label            = $lbl
            EnabledByDefault = [bool]$entry.EnabledByDefault
            RequiresElevation = if ($entry.PSObject.Properties.Name -contains 'RequiresElevation') { [bool]$entry.RequiresElevation } else { $false }
            EntryFunction    = $entry.EntryFunction
        })
        $index++
    }

    ,$result.ToArray()
}

#endregion

#region --- Rendering ---

function Show-ADHCCheckSelectionScreen {
    <#
    .SYNOPSIS
        Renders the check selection screen with checkboxes.
        Returns the current state so the caller can redraw after each key.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Categories = @(),
        [Parameter(Mandatory)][hashtable]$Selected
    )

    $ch = Get-ADHCBoxChars
    $cPrimary = Get-ADHCColor -Name 'Primary'
    $cSuccess = Get-ADHCColor -Name 'Success'
    $cMuted   = Get-ADHCColor -Name 'Muted'
    $cAccent  = Get-ADHCColor -Name 'Accent'

    Write-Host '  SELECIONE AS AUDITORIAS' -ForegroundColor $cPrimary
    Write-Host '  Digite o numero e pressione Enter para marcar/desmarcar.' -ForegroundColor $cMuted
    Write-Host ''

    # Column: number and checkbox glyph.
    foreach ($cat in $Categories) {
        $onOff = ' '
        if ($Selected[$cat.Name]) { $onOff = 'X' }

        Write-Host ('  [{0,2}] [' -f $cat.Key) -ForegroundColor $cMuted -NoNewline
        Write-Host $onOff -ForegroundColor $cSuccess -NoNewline
        Write-Host '] ' -ForegroundColor $cMuted -NoNewline
        Write-Host $cat.Label -ForegroundColor $cAccent
    }

    Write-Host ''
    Write-Host '  [A] Marcar todas' -ForegroundColor $cMuted
    Write-Host '  [N] Desmarcar todas' -ForegroundColor $cMuted
    Write-Host '  [E] Executar auditorias selecionadas' -ForegroundColor $cSuccess
    Write-Host '  [V] Voltar' -ForegroundColor $cMuted
    Write-Host ''
    Write-Host '  Digite o numero da auditoria e pressione Enter, ou A/N/E/V: ' -ForegroundColor $cPrimary -NoNewline
}

#endregion

#region --- Selection state ---

function New-ADHCSelectionState {
    <#
    .SYNOPSIS
        Builds the initial selection hashtable honoring EnabledByDefault.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Categories)

    $state = @{}
    foreach ($c in $Categories) {
        $state[$c.Name] = [bool]$c.EnabledByDefault
    }
    return $state
}

function Get-ADHCSelectedCategoryNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Categories,
        [Parameter(Mandatory)][hashtable]$Selected
    )
    $names = @()
    foreach ($c in $Categories) {
        if ($Selected[$c.Name]) { $names += $c.Name }
    }
    return ,$names
}

#endregion

#region --- Main entry ---

function Invoke-ADHCCheckSelection {
    <#
    .SYNOPSIS
        Interactive checkbox selection loop.
        Returns an object with:
            Cancelled      : $true if user chose to go back
            SelectedNames  : string[] with the category names selected
            Categories     : the catalog used (for reference)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$CheckCatalog
    )

    $categories = Get-ADHCSelectableCategories -CheckCatalog $CheckCatalog
    $selected   = New-ADHCSelectionState -Categories $categories

    while ($true) {
        Clear-ADHCScreen
        Show-ADHCBanner

        Show-ADHCCheckSelectionScreen -Categories $categories -Selected $selected

        $rawLine = [Console]::ReadLine()
        if ($null -eq $rawLine) { $rawLine = '' }
        $line = $rawLine.Trim().ToUpperInvariant()

        if ($line.Length -eq 0) { continue }

        # Numeric toggle (accepts 1..99)
        $num = 0
        if ([int]::TryParse($line, [ref]$num)) {
            $cat = $categories | Where-Object { $_.Key -eq $num } | Select-Object -First 1
            if ($cat) {
                $selected[$cat.Name] = -not $selected[$cat.Name]
            }
            continue
        }

        switch ($line) {
            'A' {
                foreach ($c in $categories) { $selected[$c.Name] = $true }
                continue
            }
            'N' {
                foreach ($c in $categories) { $selected[$c.Name] = $false }
                continue
            }
            'E' {
                $names = Get-ADHCSelectedCategoryNames -Categories $categories -Selected $selected
                if (@($names).Count -eq 0) {
                    Write-Host ''
                    Write-Host '  Selecione pelo menos uma auditoria antes de executar.' -ForegroundColor (Get-ADHCColor -Name 'Warning')
                    Start-Sleep -Seconds 2
                    continue
                }
                return [PSCustomObject]@{
                    Cancelled     = $false
                    SelectedNames = $names
                    Categories    = $categories
                }
            }
            'V' {
                return [PSCustomObject]@{
                    Cancelled     = $true
                    SelectedNames = @()
                    Categories    = $categories
                }
            }
            default {
                continue
            }
        }
    }
}

#endregion