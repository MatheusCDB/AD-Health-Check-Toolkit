Set-StrictMode -Version Latest

function Test-ADHCDcReachableFromDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Fqdn,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DomainControllers
    )
    $match = $DomainControllers | Where-Object { $_.Fqdn -eq $Fqdn } | Select-Object -First 1
    if (-not $match) { return $false }
    if ($match.Reachable -eq $false) { return $false }
    return $true
}

function Invoke-ADHCFsmo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $domain = $Context.Domain
    $results = [System.Collections.Generic.List[object]]::new()
    $dcs    = $Context.DomainControllers
    $dcCount = @($dcs).Count

    Write-ADHCLog -Level Info -Message "FSMO: evaluating roles for $domain (dcCount=$dcCount)" -Logger $Context.Logger

    # ----------------------------------------------------------------
    # 1) Domain-wide roles via Get-ADDomain
    # ----------------------------------------------------------------
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $domRoles = $null
    $domErr   = $null
    try {
        $d = Get-ADDomain -Identity $domain -ErrorAction Stop
        $domRoles = [PSCustomObject]@{
            PDCEmulator          = [string]$d.PDCEmulator
            RIDMaster            = [string]$d.RIDMaster
            InfrastructureMaster = [string]$d.InfrastructureMaster
        }
    } catch {
        $domErr = $_.Exception.Message
    }
    $sw.Stop()

    if ($domErr) {
        $results.Add((New-CheckResult `
            -CheckId 'FSMO-DOMAIN-ROLES' -Category 'FSMO' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Domain FSMO roles could not be queried' `
            -Description 'Get-ADDomain failed while reading FSMO holders.' `
            -Evidence @{ Error = $domErr } `
            -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ADDomain'
        ))
    } else {
        $roleStatuses = @{}
        $allOk = $true
        $issues = @()
        foreach ($role in @('PDCEmulator','RIDMaster','InfrastructureMaster')) {
            $holder = $domRoles.$role
            $known  = Test-ADHCDcReachableFromDiscovery -Fqdn $holder -DomainControllers $dcs
            $roleStatuses[$role] = [PSCustomObject]@{ Holder = $holder; Known = $known }
            if (-not $known) { $allOk = $false; $issues += "$role holder '$holder' is not a reachable DC known to this domain." }
        }

        if ($allOk) {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-DOMAIN-ROLES' -Category 'FSMO' `
                -Domain $domain `
                -Status 'PASS' -Severity 'High' `
                -Title 'Domain FSMO roles hosted by reachable DCs' `
                -Description 'PDC Emulator, RID Master and Infrastructure Master all point to known DCs.' `
                -Evidence @{ Roles = $domRoles } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @(
                    'Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster',
                    'netdom query fsmo'
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Get-ADDomain'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-DOMAIN-ROLES' -Category 'FSMO' `
                -Domain $domain `
                -Status 'FAIL' -Severity 'High' `
                -Title 'Domain FSMO role holder is not a reachable DC' `
                -Description 'At least one domain-wide FSMO role points to a host that is not a reachable DC.' `
                -Evidence @{ Roles = $domRoles; Issues = $issues; KnownDcs = @($dcs | ForEach-Object { $_.Fqdn }) } `
                -PotentialImpact 'Role operations may fail; authentication, RID allocation or time sync may be affected.' `
                -PossibleCauses @('DC decommissioned without transferring role','Network partition','DNS resolving role holder incorrectly') `
                -RecommendedInvestigation @('Confirm the intended role holder','Verify DNS and reachability') `
                -SuggestedCommands @(
                    'netdom query fsmo',
                    'Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster'
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Get-ADDomain'
            ))
        }
    }

    # ----------------------------------------------------------------
    # 2) Forest-wide roles via Get-ADForest
    # ----------------------------------------------------------------
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $forestRoles = $null
    $forestErr   = $null
    try {
        $f = Get-ADForest -Identity $domain -ErrorAction Stop
        $forestRoles = [PSCustomObject]@{
            SchemaMaster       = [string]$f.SchemaMaster
            DomainNamingMaster = [string]$f.DomainNamingMaster
        }
    } catch {
        $forestErr = $_.Exception.Message
    }
    $sw.Stop()

    if ($forestErr) {
        $results.Add((New-CheckResult `
            -CheckId 'FSMO-FOREST-ROLES' -Category 'FSMO' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Forest FSMO roles could not be queried' `
            -Description 'Get-ADForest failed while reading FSMO holders.' `
            -Evidence @{ Error = $forestErr } `
            -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ADForest'
        ))
    } else {
        $allOk = $true
        $issues = @()
        foreach ($role in @('SchemaMaster','DomainNamingMaster')) {
            $holder = $forestRoles.$role
            $known  = Test-ADHCDcReachableFromDiscovery -Fqdn $holder -DomainControllers $dcs
            if (-not $known) { $allOk = $false; $issues += "$role holder '$holder' is not a reachable DC known to this domain." }
        }

        if ($allOk) {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-FOREST-ROLES' -Category 'FSMO' `
                -Domain $domain `
                -Status 'PASS' -Severity 'High' `
                -Title 'Forest FSMO roles hosted by reachable DCs' `
                -Description 'Schema Master and Domain Naming Master point to known DCs.' `
                -Evidence @{ Roles = $forestRoles } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @(
                    'Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster',
                    'netdom query fsmo'
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Get-ADForest'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-FOREST-ROLES' -Category 'FSMO' `
                -Domain $domain `
                -Status 'FAIL' -Severity 'High' `
                -Title 'Forest FSMO role holder is not a reachable DC' `
                -Description 'At least one forest-wide FSMO role points to a host that is not a reachable DC.' `
                -Evidence @{ Roles = $forestRoles; Issues = $issues } `
                -PotentialImpact 'Schema and domain naming operations may fail.' `
                -PossibleCauses @('DC decommissioned without transferring role','Network partition') `
                -RecommendedInvestigation @('Confirm the intended role holder','Verify DNS and reachability') `
                -SuggestedCommands @(
                    'netdom query fsmo',
                    'Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster'
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Get-ADForest'
            ))
        }
    }

    # ----------------------------------------------------------------
    # 3) Infrastructure Master vs Global Catalog
    # ----------------------------------------------------------------
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not $domRoles) {
        $results.Add((New-CheckResult `
            -CheckId 'FSMO-INFRASTRUCTURE-GC' -Category 'FSMO' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'Infrastructure Master vs GC check skipped' `
            -Description 'Domain FSMO data was not available.' `
            -WasSkipped $true -SkipReason 'Domain FSMO query failed'
        ))
    } elseif ($dcCount -le 1) {
        $results.Add((New-CheckResult `
            -CheckId 'FSMO-INFRASTRUCTURE-GC' -Category 'FSMO' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'Infrastructure Master / GC check not applicable (single-DC domain)' `
            -Description 'The Infrastructure Master rule only matters in multi-DC domains.' `
            -Evidence @{ DomainDcCount = $dcCount; InfrastructureMaster = $domRoles.InfrastructureMaster } `
            -PotentialImpact 'No impact.' `
            -Duration $sw.Elapsed -ToolUsed 'Aggregate'
        ))
    } else {
        $allDcsAreGc = $true
        foreach ($dc in $dcs) {
            if (-not $dc.IsGlobalCatalog) { $allDcsAreGc = $false; break }
        }

        $imHolder = $domRoles.InfrastructureMaster
        $imDc = $dcs | Where-Object { $_.Fqdn -eq $imHolder } | Select-Object -First 1
        $imIsGc = $false
        if ($imDc) { $imIsGc = [bool]$imDc.IsGlobalCatalog }

        if ($allDcsAreGc) {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-INFRASTRUCTURE-GC' -Category 'FSMO' `
                -Domain $domain `
                -Status 'INFO' -Severity 'Informational' `
                -Title 'Infrastructure Master is a GC, but all DCs are GCs' `
                -Description 'When every DC is a Global Catalog, the Infrastructure Master placement rule does not apply.' `
                -Evidence @{ InfrastructureMaster = $imHolder; AllDcsAreGc = $true; DomainDcCount = $dcCount } `
                -PotentialImpact 'No impact.' `
                -Duration $sw.Elapsed -ToolUsed 'Aggregate'
            ))
        } elseif ($imIsGc) {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-INFRASTRUCTURE-GC' -Category 'FSMO' `
                -Domain $domain `
                -Status 'WARNING' -Severity 'Medium' `
                -Title 'Infrastructure Master is a Global Catalog' `
                -Description 'Infrastructure Master should not be a GC unless all DCs are GCs.' `
                -Evidence @{ InfrastructureMaster = $imHolder; ImIsGc = $true; AllDcsAreGc = $false; DomainDcCount = $dcCount } `
                -PotentialImpact 'Phantom objects may not be updated until tombstone lifetime.' `
                -PossibleCauses @('GC role added to IM host after FSMO placement','Manual FSMO move') `
                -RecommendedInvestigation @('Consider transferring Infrastructure Master to a non-GC DC, or making all DCs GCs.') `
                -SuggestedCommands @(
                    'netdom query fsmo',
                    'Get-ADDomainController -Filter * | Select-Object Name, IsGlobalCatalog'
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Aggregate'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'FSMO-INFRASTRUCTURE-GC' -Category 'FSMO' `
                -Domain $domain `
                -Status 'PASS' -Severity 'Medium' `
                -Title 'Infrastructure Master is not a Global Catalog' `
                -Description 'IM placement follows best practice for multi-DC non-all-GC domains.' `
                -Evidence @{ InfrastructureMaster = $imHolder; ImIsGc = $false; AllDcsAreGc = $false } `
                -PotentialImpact 'No impact.' `
                -Duration $sw.Elapsed -ToolUsed 'Aggregate'
            ))
        }
    }

    $results.ToArray()
}