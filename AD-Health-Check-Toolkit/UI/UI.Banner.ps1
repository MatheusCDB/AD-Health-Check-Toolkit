Set-StrictMode -Version Latest

# =============================================================================
#  UI.Banner.ps1
#  Banner ASCII art and info panel for the interactive interface.
#  Depends on UI.Console.ps1 (colors, box drawing, Unicode detection).
# =============================================================================

#region --- Banner art ---

# Unicode banner: "ADHC" in ANSI Shadow style.
$script:ADHCBannerUnicode = @(
    '  █████╗ ██████╗ ██╗  ██╗ ██████╗ ',
    ' ██╔══██╗██╔══██╗██║  ██║██╔════╝ ',
    ' ███████║██║  ██║███████║██║      ',
    ' ██╔══██║██║  ██║██╔══██║██║      ',
    ' ██║  ██║██████╔╝██║  ██║╚██████╗ ',
    ' ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ '
)

# ASCII fallback banner for consoles without Unicode support.
$script:ADHCBannerAscii = @(
    '    _    ____  _   _  ____ ',
    '   / \  |  _ \| | | |/ ___|',
    '  / _ \ | | | | |_| | |    ',
    ' / ___ \| |_| |  _  | |___ ',
    '/_/   \_\____/|_| |_|\____|'
)

function Get-ADHCBannerLines {
    [CmdletBinding()]
    param()
    if (Test-ADHCUnicodeSupport) { return $script:ADHCBannerUnicode }
    return $script:ADHCBannerAscii
}

function Show-ADHCBanner {
    <#
    .SYNOPSIS
        Prints the AD Health Check Toolkit banner at the top of the screen.
        Includes the tool name, subtitle and a one-line tagline.
    #>
    [CmdletBinding()]
    param()

    $lines = Get-ADHCBannerLines
    $primary = Get-ADHCColor -Name 'Primary'
    $accent  = Get-ADHCColor -Name 'Accent'
    $muted   = Get-ADHCColor -Name 'Muted'

    Write-Host ''
    foreach ($l in $lines) {
        Write-Host $l -ForegroundColor $primary
    }
    Write-Host ''
    Write-Host '  AD HEALTH CHECK TOOLKIT' -ForegroundColor $accent
    Write-Host '  Active Directory health assessment' -ForegroundColor $muted
    Write-Host '  PowerShell  |  Active Directory  |  DNS  |  Replication' -ForegroundColor $muted
    Write-Host ''
}

#endregion

#region --- Info panel ---

function Show-ADHCInfoPanel {
    <#
    .SYNOPSIS
        Draws a compact panel with environment information below the banner.
        Values are HTML-free plain text; no sensitive data is displayed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [string]$Domain,
        [int]$DcCount = 0
    )

    $host_    = $env:COMPUTERNAME
    $user     = "$env:USERDOMAIN\$env:USERNAME"
    $psVer    = $PSVersionTable.PSVersion.ToString()
    $now      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $domainText = '<not detected>'
    if ($Domain) { $domainText = $Domain }

    $dcText = '<unknown>'
    if ($DcCount -gt 0) { $dcText = "$DcCount" } elseif ($Domain) { $dcText = '0' }

    # Dependencies: compact ready/missing counts.
    $depReady = 0
    $depTotal = 6
    if ($Capabilities.ActiveDirectory) { $depReady++ }
    if ($Capabilities.DnsServer)       { $depReady++ }
    if ($Capabilities.Dcdiag)          { $depReady++ }
    if ($Capabilities.Repadmin)        { $depReady++ }
    if ($Capabilities.Dnscmd)          { $depReady++ }
    if ($Capabilities.W32tm)           { $depReady++ }

    $depLine = "{0}/{1} disponiveis" -f $depReady, $depTotal
    if ($depReady -lt $depTotal) {
        $depLine += "  (faltando: " + (($Capabilities.Missing) -join ', ') + ")"
    }

    $lines = @(
        ("Ferramenta     : AD Health Check Toolkit v{0}" -f $ToolVersion)
        ("PowerShell     : {0}" -f $psVer)
        ("Execucao       : {0}" -f $now)
        ("Dominio        : {0}" -f $domainText)
        ("DCs detectados : {0}" -f $dcText)
        ("Dependencias   : {0}" -f $depLine)
        ("Host / Usuario : {0}  /  {1}" -f $host_, $user)
    )

    Write-ADHCBox -Lines $lines -Title 'Ambiente' -Color 'Primary'
    Write-Host ''
}

#endregion

#region --- Composite header ---

function Show-ADHCHeader {
    <#
    .SYNOPSIS
        Banner + info panel. Clears the screen first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [string]$Domain,
        [int]$DcCount = 0
    )

    Clear-ADHCScreen
    Show-ADHCBanner
    Show-ADHCInfoPanel -ToolVersion $ToolVersion -Capabilities $Capabilities -Domain $Domain -DcCount $DcCount
}

#endregion