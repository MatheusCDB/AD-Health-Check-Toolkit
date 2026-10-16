Set-StrictMode -Version Latest

# =============================================================================
#  UI.ps1
#  Aggregator + main TUI loop.
#  Depends on UI.Console.ps1, UI.Banner.ps1, UI.MainMenu.ps1,
#  UI.CheckSelection.ps1, UI.Progress.ps1, UI.Summary.ps1, UI.ExportMenu.ps1.
# =============================================================================

#region --- Load UI modules ---

$script:ADHCUiRoot = Split-Path -Parent $PSCommandPath

foreach ($m in @(
    'UI.Console.ps1',
    'UI.Banner.ps1',
    'UI.MainMenu.ps1',
    'UI.CheckSelection.ps1',
    'UI.Progress.ps1',
    'UI.Summary.ps1',
    'UI.ExportMenu.ps1'
)) {
    $p = Join-Path $script:ADHCUiRoot $m
    if (-not (Test-Path -LiteralPath $p)) {
        throw "UI module not found: $p"
    }
    . $p
}

#endregion

#region --- Single-DC selector ---

function Invoke-ADHCSingleDcSelector {
    <#
    .SYNOPSIS
        Simple list + choose for -DcCount > 1.
        Returns the FQDN or $null if cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$DomainControllers
    )

    while ($true) {
        Clear-ADHCScreen
        Show-ADHCBanner

        Write-Host ''
        Write-Host '  SELECIONE UM DOMAIN CONTROLLER' -ForegroundColor (Get-ADHCColor -Name 'Primary')
        Write-Host ''

        $i = 1
        foreach ($dc in $DomainControllers) {
            $site = ''
            if ($dc.Site) { $site = "  (site: $($dc.Site))" }
            Write-Host ('  [{0}] {1}{2}' -f $i, $dc.Fqdn, $site) -ForegroundColor (Get-ADHCColor -Name 'Accent')
            $i++
        }
        Write-Host ''
        Write-Host '  [V] Voltar' -ForegroundColor (Get-ADHCColor -Name 'Muted')
        Write-Host ''
        Write-Host '  Opcao: ' -ForegroundColor (Get-ADHCColor -Name 'Primary') -NoNewline

        $raw = [Console]::ReadLine()
        if ($null -eq $raw) { $raw = '' }
        $line = $raw.Trim().ToUpperInvariant()

        if ($line -eq 'V') { return $null }

        $n = 0
        if ([int]::TryParse($line, [ref]$n)) {
            if ($n -ge 1 -and $n -le $DomainControllers.Count) {
                return $DomainControllers[$n - 1].Fqdn
            }
        }
    }
}

#endregion

#region --- Discovery helper for the TUI ---

function Invoke-ADHCUiDiscovery {
    <#
    .SYNOPSIS
        Runs discovery once, using the same code as the classic path.
        Returns the discovery object, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Capabilities,
        [Parameter(Mandatory)][psobject]$Logger,
        [string]$Domain
    )

    try {
        $d = Invoke-ADHCDiscovery `
            -Domain             $Domain `
            -DomainController   @() `
            -Capabilities       $Capabilities `
            -Credential         $null `
            -Logger             $Logger
        return $d
    } catch {
        return $null
    }
}

#endregion

#region --- Main TUI loop ---

function Invoke-ADHCTui {
    <#
    .SYNOPSIS
        Interactive entry point. Returns when the user chooses "Sair".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities
    )

    Initialize-ADHCConsole

    # --- Discovery is done once, kept in memory, refreshed on demand.
    $discovery = $null
    $domain    = $null
    $dcCount   = 0

    # Try to detect the domain without full discovery first (cheap).
    try {
        $domain = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
    } catch { }
    if (-not $domain) {
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($cs -and $cs.Domain) { $domain = $cs.Domain }
        } catch { }
    }

    # A logger is needed for discovery; create a tiny one in a temp folder.
    $uiLogDir = Join-Path $env:TEMP ("adhc-tui-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (-not (Test-Path -LiteralPath $uiLogDir)) { New-Item -ItemType Directory -Path $uiLogDir -Force | Out-Null }
    $uiLogger = Initialize-ADHCLog -LogDirectory $uiLogDir -ToolVersion $ToolVersion

    $statusText = 'Pronto para executar'
    $lastAssessment = $null

    while ($true) {
        # Refresh discovery snapshot for the menu header if needed.
        if ($null -eq $discovery) {
            $discovery = Invoke-ADHCUiDiscovery -Capabilities $Capabilities -Logger $uiLogger -Domain $domain
            if ($discovery -and $discovery.Success) {
                $domain  = $discovery.Domain
                $dcCount = @($discovery.DomainControllers).Count
            } else {
                $dcCount = 0
            }
        }

        $chosen = Invoke-ADHCMainMenu `
            -ToolVersion  $ToolVersion `
            -Capabilities $Capabilities `
            -Domain       $domain `
            -DcCount      $dcCount `
            -StatusText   $statusText

        switch ($chosen.Action) {

            'Exit' {
                Clear-ADHCScreen
                return
            }

            'ShowPrereqs' {
                Clear-ADHCScreen
                Show-ADHCBanner
                Write-Host ''
                Write-Host '  DEPENDENCIAS E PRE-REQUISITOS' -ForegroundColor (Get-ADHCColor -Name 'Primary')
                Write-Host ''
                $depLines = [System.Collections.Generic.List[string]]::new()
                $depLines.Add(('Active Directory PowerShell   : {0}' -f $Capabilities.ActiveDirectory))
                $depLines.Add(('DnsServer PowerShell          : {0}' -f $Capabilities.DnsServer))
                $depLines.Add(('dcdiag.exe                    : {0}' -f $Capabilities.Dcdiag))
                $depLines.Add(('repadmin.exe                  : {0}' -f $Capabilities.Repadmin))
                $depLines.Add(('dnscmd.exe                    : {0}' -f $Capabilities.Dnscmd))
                $depLines.Add(('w32tm.exe                     : {0}' -f $Capabilities.W32tm))
                $depLines.Add(('Elevated privileges           : {0}' -f $Capabilities.IsElevated))
                Write-ADHCBox -Lines $depLines -Title 'Dependencias' -Color 'Primary'
                if (@($Capabilities.Missing).Count -gt 0) {
                    Write-Host ''
                    Write-Host '  Faltando:' -ForegroundColor (Get-ADHCColor -Name 'Warning')
                    foreach ($mi in $Capabilities.Missing) {
                        Write-Host ('    - {0}' -f $mi) -ForegroundColor (Get-ADHCColor -Name 'Warning')
                    }
                }
                Wait-ADHCEnter
                continue
            }

            'SingleDc' {
                if ($null -eq $discovery -or -not $discovery.Success) {
                    $statusText = 'Discovery indisponivel'
                    continue
                }
                $dc = Invoke-ADHCSingleDcSelector -DomainControllers $discovery.DomainControllers
                if (-not $dc) { continue }
                $targetDc = $dc
                $chosen = @{ Action = 'FullAudit' }   # fall through with a DC filter
                # Deliberate fall-through: run full audit on a single DC.
                # We store the DC filter in a variable used below.
                $singleDcFilter = $targetDc
            } else {
                $singleDcFilter = $null
            }

            'FullAudit'    { $singleDcFilter = $null }
            'DeepAudit'    { $singleDcFilter = $null }
            'SelectChecks' { $singleDcFilter = $null }
            default        { $singleDcFilter = $null }
        }

        # --- Build the run parameters ---------------------------------------------------

        $runChecks  = $null
        $deepAudit  = ($chosen.Action -eq 'DeepAudit')

        if ($chosen.Action -eq 'SelectChecks') {
            $sel = Invoke-ADHCCheckSelection -CheckCatalog $script:CheckCatalog
            if ($sel.Cancelled) { continue }
            $runChecks = $sel.SelectedNames
        } elseif ($chosen.Action -eq 'FullAudit') {
            # Defaults only (no opt-ins).
            $runChecks = $null
        } elseif ($chosen.Action -eq 'DeepAudit') {
            # All categories + opt-ins on.
            $runChecks = $null
        } else {
            # Any other action handled above; skip the run.
            continue
        }

        # --- Run the assessment with progress -----------------------------------------

        $totalCats = 0
        if ($runChecks) {
            $totalCats = @($runChecks).Count
        } else {
            $base = @($script:CheckCatalog.Categories | Where-Object { $_.EnabledByDefault }).Count
            # Opt-in categories that are NOT enabled by default.
            $optIn = @('Topology','EventLogs','GroupPolicy')
            $extra = 0
            if ($deepAudit) {
                foreach ($name in $optIn) {
                    $cat = $script:CheckCatalog.Categories | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                    if ($cat -and -not $cat.EnabledByDefault) { $extra++ }
                }
            }
            $totalCats = $base + $extra
        }

        Clear-ADHCScreen
        $progressState = New-ADHCProgressState -Total $totalCats -Domain $domain -StartedAt (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Show-ADHCProgressStart -State $progressState

        $runSw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $assessment = Invoke-ADHCAssessment `
                -ScriptRoot         $ScriptRoot `
                -ToolVersion        $ToolVersion `
                -Capabilities       $Capabilities `
                -Domain             $domain `
                -DomainController   $(if ($singleDcFilter) { @($singleDcFilter) } else { @() }) `
                -Checks             $runChecks `
                -EventLookbackDays  7 `
                -IncludeEventLogs   $deepAudit `
                -IncludeDcdiag      $deepAudit `
                -IncludeTopology    $deepAudit `
                -IncludeGroupPolicy $deepAudit `
                -SkipPing           $false `
                -NoReport           $false `
                -ReportFormat       @('HTML','JSON','CSV') `
                -OnCategoryStart    { param($e) Show-ADHCProgressCategoryStart -State $progressState -Event $e } `
                -OnCategoryEnd      { param($e) Show-ADHCProgressCategoryEnd   -State $progressState -Event $e }
        } catch {
            Write-Host ''
            Write-Host ('  Falha na execucao: {0}' -f $_.Exception.Message) -ForegroundColor (Get-ADHCColor -Name 'Danger')
            Wait-ADHCEnter
            $statusText = 'Ultima execucao falhou'
            continue
        } finally {
            $runSw.Stop()
        }

        Show-ADHCProgressDone -State $progressState
        $lastAssessment = $assessment

        # --- Executive summary + actions loop -----------------------------------------

        while ($true) {
            Show-ADHCExecutiveSummary -Assessment $assessment

            Write-Host '  [1] Visualizar resultados detalhados (abrir HTML)' -ForegroundColor (Get-ADHCColor -Name 'Accent')
            Write-Host '  [2] Exportar relatorio (HTML/JSON/CSV)' -ForegroundColor (Get-ADHCColor -Name 'Accent')
            Write-Host '  [3] Executar outra auditoria' -ForegroundColor (Get-ADHCColor -Name 'Accent')
            Write-Host '  [0] Voltar ao menu principal' -ForegroundColor (Get-ADHCColor -Name 'Muted')
            Write-Host ''
            Write-Host '  Opcao: ' -ForegroundColor (Get-ADHCColor -Name 'Primary') -NoNewline

            $raw = [Console]::ReadLine()
            if ($null -eq $raw) { $raw = '' }
            $line = $raw.Trim()

            switch ($line) {
                '1' {
                    if ($assessment.ReportPaths -and $assessment.ReportPaths.Html) {
                        try { Start-Process $assessment.ReportPaths.Html } catch { }
                    } else {
                        Write-Host '  Nenhum HTML disponivel.' -ForegroundColor (Get-ADHCColor -Name 'Warning')
                        Start-Sleep -Seconds 2
                    }
                }
                '2' {
                    Invoke-ADHCExportMenu -Assessment $assessment
                }
                '3' {
                    break
                }
                '0' {
                    break
                }
                default {
                    continue
                }
            }
            if ($line -in @('3','0')) { break }
        }

        if ($line -eq '0') {
            $statusText = 'Pronto para executar'
            # Force a redraw of the header on the next iteration (discovery unchanged)
        }
    }
}

#endregion