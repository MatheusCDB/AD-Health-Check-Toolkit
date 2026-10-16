Set-StrictMode -Version Latest

function Test-ADHCCommandExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-ADHCCapabilities {
    [CmdletBinding()]
    param()

    $adModule = $false
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $adModule = $true
    } catch {
        $adModule = $false
    }

    $dnsModule = $false
    try {
        Import-Module DnsServer -ErrorAction Stop
        $dnsModule = $true
    } catch {
        $dnsModule = $false
    }

    $isElevated = $false
    try {
        $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr  = New-Object Security.Principal.WindowsPrincipal($id)
        $isElevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    $missing = [System.Collections.Generic.List[string]]::new()
    if (-not $adModule)  { $missing.Add('ActiveDirectory module (RSAT-AD-PowerShell)') }
    if (-not $dnsModule) { $missing.Add('DnsServer module (RSAT-DNS-Server)') }
    if (-not (Test-ADHCCommandExists -Name 'dcdiag'))   { $missing.Add('dcdiag.exe (RSAT-AD-Tools)') }
    if (-not (Test-ADHCCommandExists -Name 'repadmin')) { $missing.Add('repadmin.exe (RSAT-AD-Tools)') }
    if (-not (Test-ADHCCommandExists -Name 'dnscmd'))   { $missing.Add('dnscmd.exe (RSAT-DNS-Server)') }
    if (-not (Test-ADHCCommandExists -Name 'w32tm'))    { $missing.Add('w32tm.exe (built-in)') }
    if (-not $isElevated) { $missing.Add('Elevated privileges (some checks require it)') }

    [PSCustomObject]@{
        PSTypeName        = 'ADHC.Capabilities'
        ActiveDirectory   = $adModule
        DnsServer         = $dnsModule
        Dcdiag            = (Test-ADHCCommandExists -Name 'dcdiag')
        Repadmin          = (Test-ADHCCommandExists -Name 'repadmin')
        Dnscmd            = (Test-ADHCCommandExists -Name 'dnscmd')
        W32tm             = (Test-ADHCCommandExists -Name 'w32tm')
        IsElevated        = $isElevated
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Missing           = $missing.ToArray()
        ProbedAt          = (Get-Date).ToUniversalTime()
    }
}