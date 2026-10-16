Set-StrictMode -Version Latest

#region --- Helpers ---

function Get-ADHCTopologyData {
    <#
    .SYNOPSIS
        Collects sites, subnets, site links, connection objects and ISTG
        information. Each section is collected independently so that a
        failure in one section does not invalidate the others.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Domain)

    $result = [PSCustomObject]@{
        Success     = $true
        Errors      = @()
        Sites       = @()
        Subnets     = @()
        SiteLinks   = @()
        Connections = @()
        IStg        = @()
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    # --- Sites ---
    try {
        $result.Sites = @(Get-ADReplicationSite -Filter * -Server $Domain -ErrorAction Stop |
            Select-Object Name, Description,
                @{n='Subnets'; e={ @($_.Subnets) }},
                @{n='Servers'; e={ @($_.Servers) }})
    } catch {
        $errors.Add("Sites: $($_.Exception.Message)")
    }

    # --- Subnets ---
    try {
        $result.Subnets = @(Get-ADReplicationSubnet -Filter * -Server $Domain -ErrorAction Stop |
            Select-Object Name, Site, Description)
    } catch {
        $errors.Add("Subnets: $($_.Exception.Message)")
    }

    # --- Site Links ---
    # Note: 'SiteLinkBridges' is NOT a valid -Properties value for this cmdlet.
    try {
        $result.SiteLinks = @(Get-ADReplicationSiteLink -Filter * -Server $Domain `
            -Properties InterSiteTransportProtocol, Options `
            -ErrorAction Stop)
    } catch {
        $errors.Add("SiteLinks: $($_.Exception.Message)")
    }

    # --- Connection objects (per DC) ---
    try {
        $dcs = @(Get-ADDomainController -Filter * -Server $Domain -ErrorAction Stop)
        $conns = [System.Collections.Generic.List[object]]::new()
        foreach ($dc in $dcs) {
            try {
                $dcConns = @(Get-ADReplicationConnection -Filter * -Server $dc.HostName -ErrorAction Stop)
                foreach ($c in $dcConns) {
                    $conns.Add([PSCustomObject]@{
                        Dc                           = $dc.Name
                        DcHost                       = $dc.HostName
                        ConnectionName               = $c.Name
                        ReplicateFromDirectoryServer = $c.ReplicateFromDirectoryServer
                        ReplicateToDirectoryServer   = $c.ReplicateToDirectoryServer
                    })
                }
            } catch {
                # Ignore per-DC failures; we still want the others.
            }
        }
        $result.Connections = $conns.ToArray()
    } catch {
        $errors.Add("Connections: $($_.Exception.Message)")
    }

    # --- ISTG (via NTDS Site Settings) ---
    # Get-ADObject needs a DC, not a domain FQDN.
    try {
        $domainDn = (Get-ADDomain -Identity $Domain -ErrorAction Stop).DistinguishedName
        $siteSettings = @(Get-ADObject -Server $env:COMPUTERNAME `
            -SearchBase "CN=Sites,CN=Configuration,$domainDn" `
            -Filter 'objectClass -eq "nTDSSiteSettings"' `
            -Properties InterSiteTopologyGenerator `
            -ErrorAction Stop)
        $istg = foreach ($s in $siteSettings) {
            $istgDn = $s.InterSiteTopologyGenerator
            $istgHost = $null
            if ($istgDn) {
                $m = [regex]::Match([string]$istgDn, 'CN=NTDS Settings,CN=([^,]+)')
                if ($m.Success) { $istgHost = $m.Groups[1].Value }
            }
            [PSCustomObject]@{
                SiteSettings = $s.Name
                Site         = $s.DistinguishedName -replace '^CN=NTDS Site Settings,CN=([^,]+),.*$','$1'
                IstgHost     = $istgHost
                IstgDn       = $istgDn
            }
        }
        $result.IStg = @($istg)
    } catch {
        $errors.Add("ISTG: $($_.Exception.Message)")
    }

    $result.Errors  = $errors.ToArray()
    $result.Success = ($result.Sites.Count -gt 0)   # At minimum sites must work.
    return $result
}

function Get-ADHCDnsNameFromReplDn {
    <#
    .SYNOPSIS
        Extracts the leading CN from a DirectoryServer DN like
        "CN=AD01,CN=Servers,CN=Default-First-Site-Name,..." returning "AD01".
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Dn)
    if (-not $Dn) { return $null }
    $m = [regex]::Match([string]$Dn, '^CN=([^,]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCTopology {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $domain  = $Context.Domain
    $dcs     = @($Context.DomainControllers)
    $dcCount = $dcs.Count

    $results = [System.Collections.Generic.List[object]]::new()

    Write-ADHCLog -Level Info -Message "Topology: evaluating domain $domain (dcCount=$dcCount)" -Logger $Context.Logger

    $topo = Get-ADHCTopologyData -Domain $domain

    if (-not $topo.Success) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-QUERY' -Category 'Topology' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'Could not enumerate topology objects' `
            -Description 'One or more Get-ADReplication* calls failed.' `
            -Evidence @{ Errors = $topo.Errors } `
            -IsInconclusive $true -ToolUsed 'Get-ADReplication*'
        ))
        return $results.ToArray()
    }

    # ------------------------------------------------------------------
    # TOPO-SITES
    # ------------------------------------------------------------------
    $siteCount = @($topo.Sites).Count
    $siteEvidence = @{
        Count = $siteCount
        Sites = @($topo.Sites | ForEach-Object { $_.Name })
    }
    if ($siteCount -lt 1) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITES' -Category 'Topology' `
            -Domain $domain `
            -Status 'FAIL' -Severity 'Medium' `
            -Title 'No sites configured' `
            -Description 'The domain has no sites; replication and DC Locator rely on sites.' `
            -Evidence $siteEvidence `
            -PotentialImpact 'DC Locator may fail to return site-aware results.' `
            -PossibleCauses @('Sites were deleted','Unexpected forest state') `
            -RecommendedInvestigation @('Verify AD Sites and Services.') `
            -SuggestedCommands @('Get-ADReplicationSite -Filter *') `
            -ToolUsed 'Get-ADReplicationSite'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITES' -Category 'Topology' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title "$siteCount site(s) configured" `
            -Description 'At least one site exists.' `
            -Evidence $siteEvidence `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADReplicationSite -Filter *') `
            -ToolUsed 'Get-ADReplicationSite'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-SUBNETS (INFO when single-site + 0 subnets; WARNING when multi-site + 0 subnets)
    # ------------------------------------------------------------------
    $subnetCount = @($topo.Subnets).Count
    $subnetEvidence = @{
        Count      = $subnetCount
        SiteCount  = $siteCount
        Subnets    = @($topo.Subnets | ForEach-Object { "$($_.Name) => $($_.Site)" })
    }

    if ($subnetCount -eq 0 -and $siteCount -le 1) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNETS' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'No subnets associated with sites (single-site domain)' `
            -Description 'Tolerable in single-site domains; becomes relevant when more sites are added.' `
            -Evidence $subnetEvidence `
            -PotentialImpact 'No impact now; consider mapping subnets if you plan to add another site.' `
            -PossibleCauses @('Domain never had Sites and Services configured') `
            -RecommendedInvestigation @('Optional: define subnets and associate with the site.') `
            -SuggestedCommands @('Get-ADReplicationSubnet -Filter *','New-ADReplicationSubnet -Name "10.0.0.0/24" -Site "Default-First-Site-Name"') `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    } elseif ($subnetCount -eq 0 -and $siteCount -gt 1) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNETS' -Category 'Topology' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title 'No subnets associated with sites in a multi-site domain' `
            -Description 'Subnets should be mapped to sites for DC Locator to work well.' `
            -Evidence $subnetEvidence `
            -PotentialImpact 'Clients may authenticate against a DC in a distant site.' `
            -PossibleCauses @('Sites configured without subnet associations') `
            -RecommendedInvestigation @('Map each subnet to the correct site.') `
            -SuggestedCommands @('Get-ADReplicationSubnet -Filter *') `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNETS' -Category 'Topology' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title "$subnetCount subnet(s) associated with sites" `
            -Description 'Subnets are mapped to at least one site.' `
            -Evidence $subnetEvidence `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADReplicationSubnet -Filter *') `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-SUBNET-ORPHAN
    # ------------------------------------------------------------------
    $orphans = @()
    foreach ($s in $topo.Subnets) {
        $siteValue = $s.Site
        if (-not $siteValue) { $orphans += $s.Name }
    }
    if ($subnetCount -eq 0) {
        # Nothing to check; emit INFO to keep the check IDs stable.
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNET-ORPHAN' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'No subnets to evaluate for orphan status' `
            -Description 'No subnets are defined.' `
            -Evidence @{ Count = 0 } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    } elseif ($orphans.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNET-ORPHAN' -Category 'Topology' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title 'All subnets are associated with a site' `
            -Description 'No orphan subnets detected.' `
            -Evidence @{ Count = $subnetCount } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADReplicationSubnet -Filter *') `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SUBNET-ORPHAN' -Category 'Topology' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title "$($orphans.Count) subnet(s) without a site" `
            -Description 'These subnets are not associated with any site.' `
            -Evidence @{ Count = $orphans.Count; Subnets = $orphans } `
            -PotentialImpact 'Clients in those subnets may pick a DC from a distant site.' `
            -PossibleCauses @('Subnet created without site association','Site renamed or removed') `
            -RecommendedInvestigation @('Associate each subnet with the correct site.') `
            -SuggestedCommands @('Get-ADReplicationSubnet -Filter *') `
            -ToolUsed 'Get-ADReplicationSubnet'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-DC-SITE-ASSIGNMENT
    # ------------------------------------------------------------------
    $validSites = @{}
    foreach ($s in $topo.Sites) { $validSites[$s.Name] = $true }
    $unassigned = @()
    foreach ($dc in $dcs) {
        if (-not $dc.Site -or -not $validSites.ContainsKey($dc.Site)) {
            $unassigned += "$($dc.Name) ($($dc.Site))"
        }
    }
    if ($unassigned.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-DC-SITE-ASSIGNMENT' -Category 'Topology' `
            -Domain $domain `
            -Status 'PASS' -Severity 'High' `
            -Title 'All DCs are in valid sites' `
            -Description 'Every discovered DC belongs to a configured site.' `
            -Evidence @{ Dcs = @($dcs | ForEach-Object { "$($_.Name) => $($_.Site)" }) } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADDomainController -Filter * | Select-Object Name, Site') `
            -ToolUsed 'Aggregate'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-DC-SITE-ASSIGNMENT' -Category 'Topology' `
            -Domain $domain `
            -Status 'FAIL' -Severity 'High' `
            -Title "$($unassigned.Count) DC(s) with invalid or missing site" `
            -Description 'DCs must be associated with a valid site.' `
            -Evidence @{ Unassigned = $unassigned; ValidSites = @($validSites.Keys) } `
            -PotentialImpact 'DC Locator and inter-site replication may misbehave for these DCs.' `
            -PossibleCauses @('DC moved to a site that no longer exists','Manual topology edit') `
            -RecommendedInvestigation @('Verify each DC site in AD Sites and Services.') `
            -SuggestedCommands @('Get-ADDomainController -Filter * | Select-Object Name, Site') `
            -ToolUsed 'Aggregate'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-SITE-LINKS
    # ------------------------------------------------------------------
    $slCount = @($topo.SiteLinks).Count
    $slEvidence = @{
        Count = $slCount
        Links = @($topo.SiteLinks | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.Name
                Cost     = $_.Cost
                Frequency = $_.ReplicationFrequencyInMinutes
                Transport = [string]$_.InterSiteTransportProtocol
                SitesIncluded = @($_.SitesIncluded).Count
            }
        })
    }
    if ($slCount -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITE-LINKS' -Category 'Topology' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title 'No site links configured' `
            -Description 'Site links drive inter-site replication.' `
            -Evidence $slEvidence `
            -PotentialImpact 'If a second site is added, replication between sites will not occur.' `
            -PossibleCauses @('Single-site forest','Site links deleted') `
            -RecommendedInvestigation @('Confirm whether this is intended.') `
            -SuggestedCommands @('Get-ADReplicationSiteLink -Filter *') `
            -ToolUsed 'Get-ADReplicationSiteLink'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITE-LINKS' -Category 'Topology' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title "$slCount site link(s) configured" `
            -Description 'Site links are present.' `
            -Evidence $slEvidence `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADReplicationSiteLink -Filter * -Properties *') `
            -ToolUsed 'Get-ADReplicationSiteLink'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-SITE-LINK-BRIDGES
    # ------------------------------------------------------------------
    $bridges = @()
    foreach ($sl in $topo.SiteLinks) {
        $bridgeList = @($sl.SiteLinkBridges)
        if ($bridgeList.Count -gt 0) {
            $bridges += [PSCustomObject]@{
                SiteLink = $sl.Name
                Bridges  = $bridgeList
            }
        }
    }
    if ($bridges.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITE-LINK-BRIDGES' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Low' `
            -Title 'No site link bridges configured' `
            -Description 'Site link bridges are optional; KCC transitive behavior is usually sufficient.' `
            -Evidence @{ Count = 0 } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADReplicationSiteLinkBridge -Filter *') `
            -ToolUsed 'Get-ADReplicationSiteLink'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-SITE-LINK-BRIDGES' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Low' `
            -Title "$($bridges.Count) site link bridge(s) configured" `
            -Description 'Site link bridges are explicitly configured.' `
            -Evidence @{ Bridges = $bridges } `
            -PotentialImpact 'Bridgeheads must be well-defined; review manually.' `
            -SuggestedCommands @('Get-ADReplicationSiteLinkBridge -Filter * -Properties *') `
            -ToolUsed 'Get-ADReplicationSiteLink'
        ))
    }

    # ------------------------------------------------------------------
    # TOPO-CONNECTIONS
    # ------------------------------------------------------------------
    $connCount = @($topo.Connections).Count
    if ($dcCount -le 1) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-CONNECTIONS' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'KCC connections not applicable (single-DC domain)' `
            -Description 'Connection objects only exist when there are 2+ DCs.' `
            -Evidence @{ DomainDcCount = $dcCount; ConnectionCount = $connCount } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Get-ADReplicationConnection'
        ))
    } elseif ($connCount -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-CONNECTIONS' -Category 'Topology' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title 'No KCC connection objects found across DCs' `
            -Description 'Expected at least one inbound connection per DC in multi-DC domains.' `
            -Evidence @{ DomainDcCount = $dcCount; ConnectionCount = 0 } `
            -PotentialImpact 'Replication may not run until KCC creates the connections.' `
            -PossibleCauses @('KCC disabled','Connection objects manually deleted','Permission issue reading them') `
            -RecommendedInvestigation @('Check KCC event log on each DC; run repadmin /kcc.') `
            -SuggestedCommands @('repadmin /kcc','repadmin /showconn') `
            -ToolUsed 'Get-ADReplicationConnection'
        ))
    } else {
        # Group per DC and confirm each DC has at least one inbound connection.
        $perDc = @{}
        foreach ($c in $topo.Connections) {
            if (-not $perDc.ContainsKey($c.Dc)) { $perDc[$c.Dc] = 0 }
            $perDc[$c.Dc]++
        }
        $noInbound = @()
        foreach ($dc in $dcs) {
            if (-not $perDc.ContainsKey($dc.Name)) { $noInbound += $dc.Name }
        }
        if ($noInbound.Count -eq 0) {
            $results.Add((New-CheckResult `
                -CheckId 'TOPO-CONNECTIONS' -Category 'Topology' `
                -Domain $domain `
                -Status 'PASS' -Severity 'Medium' `
                -Title "$connCount KCC connection object(s) across $dcCount DCs" `
                -Description 'Every DC has at least one inbound connection object.' `
                -Evidence @{ Total = $connCount; PerDc = $perDc } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @('repadmin /showconn') `
                -ToolUsed 'Get-ADReplicationConnection'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TOPO-CONNECTIONS' -Category 'Topology' `
                -Domain $domain `
                -Status 'WARNING' -Severity 'Medium' `
                -Title "$($noInbound.Count) DC(s) without any inbound connection" `
                -Description 'These DCs have no connection objects; replication may not reach them.' `
                -Evidence @{ Total = $connCount; PerDc = $perDc; DcsWithoutInbound = $noInbound } `
                -PotentialImpact 'Replication from other DCs may not occur.' `
                -PossibleCauses @('KCC did not create the connections yet','Manual cleanup') `
                -RecommendedInvestigation @('Run repadmin /kcc and recheck.') `
                -SuggestedCommands @('repadmin /kcc','repadmin /showconn') `
                -ToolUsed 'Get-ADReplicationConnection'
            ))
        }
    }

    # ------------------------------------------------------------------
    # TOPO-ISTG
    # ------------------------------------------------------------------
    if (@($topo.IStg).Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-ISTG' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'ISTG not enumerated' `
            -Description 'NTDS Site Settings objects were not returned.' `
            -Evidence @{ Count = 0 } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADObject -Filter ''objectClass -eq "nTDSSiteSettings"'' -SearchBase "CN=Sites,CN=Configuration,<DomainDN>" -Properties InterSiteTopologyGenerator') `
            -ToolUsed 'Get-ADObject'
        ))
    } else {
        $istgSummary = @($topo.IStg | ForEach-Object { "$($_.Site) => $($_.IstgHost)" })
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-ISTG' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Informational' `
            -Title "ISTG per site: $($istgSummary -join '; ')" `
            -Description 'The ISTG is chosen automatically; this check is informational.' `
            -Evidence @{ Sites = $topo.IStg } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('Get-ADObject -Filter ''objectClass -eq "nTDSSiteSettings"'' -SearchBase "CN=Sites,CN=Configuration,<DomainDN>" -Properties InterSiteTopologyGenerator') `
            -ToolUsed 'Get-ADObject'
        ))
    }

    # ----- Aqui entra o bloco TOPO-PARTIAL -----
    if (@($topo.Errors).Count -gt 0) {
        $results.Add((New-CheckResult `
            -CheckId 'TOPO-PARTIAL' -Category 'Topology' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'Some topology sections could not be collected' `
            -Description 'One or more per-section queries failed; see Evidence.Errors.' `
            -Evidence @{ Errors = $topo.Errors } `
            -PotentialImpact 'Topology results are partially incomplete.' `
            -RecommendedInvestigation @('Review each error; rerun on the affected DC if needed.') `
            -ToolUsed 'Aggregate'
        ))
    }
    # ----- Fim do bloco TOPO-PARTIAL -----

    $results.ToArray()
}

#endregion