Set-StrictMode -Version Latest

function Resolve-ADHCDomainName {
    [CmdletBinding()]
    param([string]$Domain)

    if ($Domain) { return $Domain }

    try {
        if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
            return (Get-ADDomain).DNSRoot
        }
    } catch { }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Domain) { return $cs.Domain }
    } catch { }

    throw 'Unable to determine domain FQDN. Specify -Domain explicitly.'
}

function Get-ADHCFSMORoles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Domain)

    $result = [ordered]@{
        PDCEmulator         = $null
        RIDMaster           = $null
        InfrastructureMaster= $null
        SchemaMaster        = $null
        DomainNamingMaster  = $null
        Errors              = @()
    }

    try {
        $d = Get-ADDomain -Identity $Domain
        $result.PDCEmulator          = $d.PDCEmulator
        $result.RIDMaster            = $d.RIDMaster
        $result.InfrastructureMaster = $d.InfrastructureMaster
    } catch { $result.Errors += "Domain FSMO query failed: $($_.Exception.Message)" }

    try {
        $f = Get-ADForest -Identity $Domain
        $result.SchemaMaster        = $f.SchemaMaster
        $result.DomainNamingMaster  = $f.DomainNamingMaster
    } catch { $result.Errors += "Forest FSMO query failed: $($_.Exception.Message)" }

    [PSCustomObject]$result
}

function Get-ADHCDomainControllersList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [string[]]$Filter,
        [Parameter(Mandatory)][psobject]$Capabilities
    )

    if (-not $Capabilities.ActiveDirectory) {
        throw 'ActiveDirectory module is not available; cannot enumerate DCs.'
    }

    $dcs = Get-ADDomainController -Filter * -Server $Domain -ErrorAction Stop

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($dc in $dcs) {
        if ($Filter -and -not ($Filter -contains $dc.HostName -or $Filter -contains $dc.Name)) {
            continue
        }

        $ipv4 = $null
        try {
            $addrs = [System.Net.Dns]::GetHostAddresses($dc.HostName) |
                     Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            if ($addrs) { $ipv4 = $addrs[0].IPAddressToString }
        } catch { }

        $list.Add([PSCustomObject]@{
            PSTypeName             = 'ADHC.DomainController'
            Name                   = $dc.Name
            Fqdn                   = $dc.HostName
            IPv4                   = $ipv4
            Site                   = $dc.Site
            OperatingSystem        = $dc.OperatingSystem
            OperatingSystemVersion = $dc.OperatingSystemVersion
            IsGlobalCatalog        = $dc.IsGlobalCatalog
            IsReadOnly             = $dc.IsReadOnly
            IsRodc                 = $dc.IsReadOnly
            Enabled                = $dc.Enabled
            Reachable              = $null
            DiscoveryError         = $null
        })
    }
    ,$list.ToArray()
}

function Invoke-ADHCDiscovery {
    [CmdletBinding()]
    param(
        [string]$Domain,
        [string[]]$DomainController,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [PSCredential]$Credential,
        [psobject]$Logger
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $domain = Resolve-ADHCDomainName -Domain $Domain
        Write-ADHCLog -Level Info -Message "Resolved domain: $domain" -Logger $Logger

        if (-not $Capabilities.ActiveDirectory) {
            throw 'ActiveDirectory PowerShell module is required for discovery. Install RSAT-AD-PowerShell.'
        }

        $dcList = Get-ADHCDomainControllersList -Domain $domain -Filter $DomainController -Capabilities $Capabilities
        if (-not $dcList -or $dcList.Count -eq 0) {
            throw "No domain controllers discovered for domain $domain."
        }

        $fsmo = Get-ADHCFSMORoles -Domain $domain

        $forest = $null
        try {
            $f = Get-ADForest -Identity $domain
            $forest = [PSCustomObject]@{
                Name               = $f.Name
                ForestMode         = $f.ForestMode.ToString()
                RootDomain         = $f.RootDomain
                GlobalCatalogs     = $f.GlobalCatalogs
                Sites              = $f.Sites
                Domains            = $f.Domains
                SchemaMaster       = $f.SchemaMaster
                DomainNamingMaster = $f.DomainNamingMaster
                UPNSuffixes        = $f.UPNSuffixes
            }
        } catch {
            Write-ADHCLog -Level Warning -Message "Forest query failed: $($_.Exception.Message)" -Logger $Logger
        }

        $sites = @()
        try {
            $sites = Get-ADReplicationSite -Filter * -Server $domain |
                     Select-Object Name, Description, @{n='DistinguishedName';e={$_.DistinguishedName}}
        } catch {
            Write-ADHCLog -Level Warning -Message "Sites query failed: $($_.Exception.Message)" -Logger $Logger
        }

        [PSCustomObject]@{
            PSTypeName        = 'ADHC.Discovery'
            Success           = $true
            Domain            = $domain
            DomainControllers = $dcList
            FSMO              = $fsmo
            Forest            = $forest
            Sites             = $sites
            Duration          = $sw.Elapsed
            ErrorMessage      = $null
        }
    } catch {
        [PSCustomObject]@{
            PSTypeName        = 'ADHC.Discovery'
            Success           = $false
            Domain            = $Domain
            DomainControllers = @()
            FSMO              = $null
            Forest            = $null
            Sites             = @()
            Duration          = $sw.Elapsed
            ErrorMessage      = $_.Exception.Message
        }
    } finally {
        $sw.Stop()
    }
}