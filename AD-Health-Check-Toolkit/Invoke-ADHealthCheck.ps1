<#
.SYNOPSIS
    AD Health Check Toolkit - entry point.

.DESCRIPTION
    Read-only diagnostic tool for Active Directory Domain Services.
    Must be executed from inside a Domain Controller.
    Requires PowerShell 7 or later (auto-installs and relaunches if needed).

.PARAMETER Interactive
    Reserved for the interactive TUI. Currently ignored; will be wired
    when the TUI is delivered.
#>
[CmdletBinding()]
param(
    [string]$Domain,
    [string[]]$DomainController,
    [string]$OutputPath,
    [ValidateSet(
        'Connectivity','Services','Replication','Topology','DNS',
        'SysvolNetlogon','FSMO','TimeSynchronization','EventLogs',
        'GroupPolicy','DCDiag'
    )]
    [string[]]$Checks,
    [ValidateRange(1, 365)]
    [int]$EventLookbackDays = 7,
    [switch]$IncludeEventLogs,
    [switch]$IncludeSecurityLog,
    [switch]$IncludeDnsDetails,
    [switch]$IncludeTopology,
    [switch]$IncludeDcdiag,
    [switch]$IncludeGroupPolicy,
    [switch]$SkipPing,
    [switch]$PassThru,
    [PSCredential]$Credential,
    [switch]$SkipAutoInstall,
    [ValidateRange(1, 50)]
    [int]$ThrottleLimit = 5,
    [switch]$NoReport,
    [ValidateSet('HTML','JSON','CSV')]
    [string[]]$ReportFormat = @('HTML','JSON','CSV'),
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$script:ADHCVersion = '0.1.0'

#region --- PowerShell 7 bootstrap ---
function Get-ADHCPwshPath {
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        (Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell/7/pwsh.exe')
    )) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Install-ADHCPowerShell7 {
    [CmdletBinding()]
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host 'PowerShell 7 not found. Attempting installation...' -ForegroundColor Yellow }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            & $winget.Source install --id Microsoft.PowerShell --silent `
                --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } catch { }
    }
    if (Get-ADHCPwshPath) { return $true }

    $msiUrl  = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi'
    $msiPath = Join-Path $env:TEMP 'ADHC-PowerShell-7.4.6-win-x64.msi'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
        $p = Start-Process msiexec.exe -ArgumentList @(
            '/i', "`"$msiPath`"", '/quiet', '/norestart', 'ADD_PATH=1'
        ) -Wait -PassThru
        Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -ne 0) { return $false }
    } catch {
        if (-not $Quiet) { Write-Warning "PS7 installation failed: $($_.Exception.Message)" }
        return $false
    }
    return [bool](Get-ADHCPwshPath)
}

function Restart-ADHCInPwsh {
    param(
        [Parameter(Mandatory)][string]$PwshPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($key in $BoundParameters.Keys) {
        $value = $BoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $argList += "-$key" }
        } elseif ($value -is [array]) {
            $argList += "-$key"; $argList += ($value -join ',')
        } elseif ($value -is [System.Management.Automation.PSCredential]) {
            Write-Warning "Credential cannot survive the PS7 relaunch. Re-run with -Credential in pwsh."
        } else {
            $argList += "-$key"; $argList += [string]$value
        }
    }
    & $PwshPath @argList
    exit $LASTEXITCODE
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshPath = Get-ADHCPwshPath
    if (-not $pwshPath -and -not $SkipAutoInstall) {
        if (Install-ADHCPowerShell7) { $pwshPath = Get-ADHCPwshPath }
    }
    if (-not $pwshPath) {
        throw "This tool requires PowerShell 7+. Install it from https://aka.ms/powershell or re-run without -SkipAutoInstall."
    }
    Write-Host "Relaunching under $pwshPath ..." -ForegroundColor Cyan
    Restart-ADHCInPwsh -PwshPath $pwshPath -BoundParameters $PSBoundParameters -ScriptPath $PSCommandPath
    return
}
#endregion

#region --- Load modules & config ---
$scriptRoot = Split-Path -Parent $PSCommandPath
$corePsd1   = Join-Path $scriptRoot 'Core/Core.psd1'
$configDir  = Join-Path $scriptRoot 'Config'

foreach ($p in @($corePsd1, (Join-Path $configDir 'Defaults.psd1'),
                 (Join-Path $configDir 'CheckCatalog.psd1'),
                 (Join-Path $configDir 'SeverityRules.psd1'))) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required file not found: $p" }
}

Import-Module $corePsd1 -Force -ErrorAction Stop

$script:Defaults     = Import-PowerShellDataFile -LiteralPath (Join-Path $configDir 'Defaults.psd1')
$script:CheckCatalog = Import-PowerShellDataFile -LiteralPath (Join-Path $configDir 'CheckCatalog.psd1')
$script:SeverityRules= Import-PowerShellDataFile -LiteralPath (Join-Path $configDir 'SeverityRules.psd1')
Set-ADHCSeverityRules -Rules $script:SeverityRules
Set-ADHCDefaults       -Defaults $script:Defaults

# Shared modules used by the orchestrator and by the report generator.
foreach ($m in @('Discovery.ps1','HealthScoring.ps1','ReportGenerator.ps1','Orchestrator.ps1')) {
    $p = Join-Path $scriptRoot "Modules/$m"
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required module not found: $p"
    }
    . $p
}
#endregion

#region --- Capability probe ---
$capabilities = Get-ADHCCapabilities
Write-Host ''
Write-Host 'AD Health Check Toolkit' -ForegroundColor Cyan
Write-Host ("  Host:         {0}" -f $env:COMPUTERNAME)
Write-Host ("  User:         {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
Write-Host ("  PowerShell:   {0}" -f $PSVersionTable.PSVersion.ToString())
Write-Host ''
Write-Host ("  Capabilities: AD={0}  DnsSrv={1}  dcdiag={2}  repadmin={3}  dnscmd={4}  w32tm={5}  elevated={6}" -f `
    $capabilities.ActiveDirectory, $capabilities.DnsServer, $capabilities.Dcdiag,
    $capabilities.Repadmin, $capabilities.Dnscmd, $capabilities.W32tm, $capabilities.IsElevated)
foreach ($missing in $capabilities.Missing) {
    Write-Host ("  ! Missing: {0}" -f $missing) -ForegroundColor Yellow
}
Write-Host ''
#endregion

#region --- Interactive TUI routing ---
$useInteractive = $Interactive.IsPresent -or ($PSBoundParameters.Count -eq 0)

if ($useInteractive) {
    $uiModule = Join-Path $scriptRoot 'UI/UI.ps1'
    if (-not (Test-Path -LiteralPath $uiModule)) {
        throw "Interactive UI module not found: $uiModule"
    }
    . $uiModule

    Invoke-ADHCTui `
        -ScriptRoot   $scriptRoot `
        -ToolVersion  $script:ADHCVersion `
        -Capabilities $capabilities
    return
}
#endregion

#region --- Assessment ---
try {
    $assessment = Invoke-ADHCAssessment `
        -ScriptRoot         $scriptRoot `
        -ToolVersion        $script:ADHCVersion `
        -Capabilities       $capabilities `
        -Domain             $Domain `
        -DomainController   $DomainController `
        -OutputPath         $OutputPath `
        -Checks             $Checks `
        -EventLookbackDays  $EventLookbackDays `
        -IncludeEventLogs   ([bool]$IncludeEventLogs) `
        -IncludeSecurityLog ([bool]$IncludeSecurityLog) `
        -IncludeDnsDetails  ([bool]$IncludeDnsDetails) `
        -IncludeDcdiag      ([bool]$IncludeDcdiag) `
        -IncludeTopology    ([bool]$IncludeTopology) `
        -IncludeGroupPolicy ([bool]$IncludeGroupPolicy) `
        -SkipPing           ([bool]$SkipPing) `
        -Credential         $Credential `
        -ThrottleLimit      $ThrottleLimit `
        -NoReport           ([bool]$NoReport) `
        -ReportFormat       $ReportFormat
} catch {
    Write-Host ("Assessment failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    throw
}
#endregion

#region --- Console summary ---
$discovery   = $assessment.Consolidated.Discovery
$allResults  = $assessment.Consolidated.Results
$runMetadata = $assessment.Consolidated.Metadata
$summary     = $assessment.Summary
$score       = $assessment.Score
$reportPaths = $assessment.ReportPaths
$logger      = $assessment.Logger

Write-Host ''
Write-Host 'AD Health Check completed.' -ForegroundColor Green
Write-Host ("  Domain:      {0}" -f $discovery.Domain)
Write-Host ("  DCs found:   {0} ({1} unreachable)" -f $runMetadata.DcsDiscovered, $runMetadata.DcsUnreachable)
Write-Host ("  Checks:      {0}  PASS:{1}  WARN:{2}  FAIL:{3}  INFO:{4}  UNKNOWN:{5}" -f `
    $allResults.Count, $summary.PASS, $summary.WARNING, $summary.FAIL, $summary.INFO, $summary.UNKNOWN)
Write-Host ("  Score:       {0}/100  ({1})" -f $score.Score, $score.BandLabel) -ForegroundColor Cyan
Write-Host ("  Output:      {0}" -f $assessment.OutputPath)
if ($reportPaths) {
    if ($reportPaths.Html) { Write-Host ("  HTML:        {0}" -f $reportPaths.Html) }
    if ($reportPaths.Json) { Write-Host ("  JSON:        {0}" -f $reportPaths.Json) }
    if ($reportPaths.Csv)  { Write-Host ("  CSV:         {0}" -f $reportPaths.Csv)  }
}
Write-Host ("  Log:         {0}" -f $logger.LogFilePath)
Write-Host ''
#endregion

if ($PassThru) { $assessment.Consolidated }