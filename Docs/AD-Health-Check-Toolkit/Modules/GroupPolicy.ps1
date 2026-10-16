Set-StrictMode -Version Latest

#region --- Constants ---

# Canonical GUIDs of the two policies that must exist in every domain,
# regardless of their localized display name.
$script:ADHCDefaultGpoGuids = @{
    'Default Domain Policy'             = '31b2f340-016d-11d2-945f-00c04fb984f9'
    'Default Domain Controllers Policy' = '6ac1786c-016f-11d2-945f-00c04fb984f9'
}

#endregion

#region --- Helpers ---

function Import-ADHCGroupPolicyModule {
    <#
    .SYNOPSIS
        Imports the GroupPolicy module on PowerShell 7 using -SkipEditionCheck
        to avoid the WinPSCompatSession warning. Returns $true on success.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command Get-GPO -ErrorAction SilentlyContinue) { return $true }

    try {
        Import-Module GroupPolicy -SkipEditionCheck -ErrorAction Stop
        return [bool](Get-Command Get-GPO -ErrorAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Get-ADHCAdGpos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Domain)

    try {
        $gpos = @(Get-GPO -All -Domain $Domain -ErrorAction Stop)
        $normalized = foreach ($g in $gpos) {
            $idString = ''
            if ($g.Id) {
                if ($g.Id -is [guid]) { $idString = $g.Id.ToString() }
                else { $idString = [string]$g.Id }
            }
            [PSCustomObject]@{
                Id          = $idString.ToLowerInvariant()
                DisplayName = [string]$g.DisplayName
                GpoStatus   = if ($g.GpoStatus) { [string]$g.GpoStatus } else { $null }
                Owner       = if ($g.Owner)     { [string]$g.Owner }     else { $null }
            }
        }
        [PSCustomObject]@{ Success = $true; Gpos = @($normalized); Error = $null }
    } catch {
        [PSCustomObject]@{ Success = $false; Gpos = @(); Error = $_.Exception.Message }
    }
}

function Get-ADHCSysvolPolicyFolders {
    <#
    .SYNOPSIS
        Enumerates {GUID} folders under \\<DC>\SYSVOL\<domain>\Policies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DcFqdn,
        [Parameter(Mandatory)][string]$Domain
    )

    $uncPath = "\\$DcFqdn\SYSVOL\$Domain\Policies"
    try {
        $folders = @(Get-ChildItem -LiteralPath $uncPath -Directory -ErrorAction Stop)
        $normalized = foreach ($f in $folders) {
            [PSCustomObject]@{
                Name          = $f.Name
                Guid          = $f.Name.Trim('{','}').ToLowerInvariant()
                LastWriteTime = $f.LastWriteTime
            }
        }
        [PSCustomObject]@{ Success = $true; UncPath = $uncPath; Folders = @($normalized); Error = $null }
    } catch {
        [PSCustomObject]@{ Success = $false; UncPath = $uncPath; Folders = @(); Error = $_.Exception.Message }
    }
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCGroupPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $domain  = $Context.Domain
    $dcs     = @($Context.DomainControllers)
    $dcCount = $dcs.Count

    $results = [System.Collections.Generic.List[object]]::new()

    Write-ADHCLog -Level Info -Message "GroupPolicy: evaluating domain $domain (dcCount=$dcCount)" -Logger $Context.Logger

    # ------------------------------------------------------------------
    # Module availability
    # ------------------------------------------------------------------
    $moduleOk = Import-ADHCGroupPolicyModule

    $moduleStatus = 'PASS'
    if (-not $moduleOk) { $moduleStatus = 'UNKNOWN' }

    $moduleTitle = 'GroupPolicy module available'
    if (-not $moduleOk) { $moduleTitle = 'GroupPolicy module NOT available' }

    $moduleImpact = 'No impact.'
    if (-not $moduleOk) { $moduleImpact = 'GPO checks cannot run without the GroupPolicy module.' }

    $results.Add((New-CheckResult `
        -CheckId 'GPO-MODULE' -Category 'GroupPolicy' `
        -Domain $domain `
        -Status $moduleStatus -Severity 'Informational' `
        -Title $moduleTitle `
        -Description 'Reports whether Get-GPO and related cmdlets can be imported on this host.' `
        -Evidence @{ Available = $moduleOk } `
        -PotentialImpact $moduleImpact `
        -PossibleCauses @('RSAT Group Policy Management Tools not installed') `
        -RecommendedInvestigation @('Install RSAT Group Policy Management Tools if GPO checks are desired.') `
        -SuggestedCommands @('Import-Module GroupPolicy -SkipEditionCheck','Get-Command Get-GPO') `
        -IsInconclusive (-not $moduleOk) `
        -ToolUsed 'Import-Module'
    ))

    if (-not $moduleOk) {
        # Without the module, emit stub results so check IDs remain consistent.
        foreach ($id in @('GPO-SYSVOL-ACCESS','GPO-CNTFS-READY','GPO-COUNT-MATCH','GPO-SYSVOL-ORPHAN','GPO-AD-ORPHAN','GPO-DEFAULT-POLICIES')) {
            $results.Add((New-CheckResult `
                -CheckId $id -Category 'GroupPolicy' `
                -Domain $domain `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "GroupPolicy module not available" `
                -Description 'This check requires the GroupPolicy module.' `
                -WasSkipped $true -SkipReason 'GroupPolicy module not available'
            ))
        }
        if ($dcCount -le 1) {
            $results.Add((New-CheckResult `
                -CheckId 'GPO-DFSR-BACKLOG' -Category 'GroupPolicy' `
                -Domain $domain `
                -Status 'INFO' -Severity 'Medium' `
                -Title 'DFSR backlog check not applicable (single-DC domain)' `
                -Evidence @{ DomainDcCount = $dcCount } `
                -PotentialImpact 'No impact.' `
                -ToolUsed 'Aggregate'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'GPO-DFSR-BACKLOG' -Category 'GroupPolicy' `
                -Domain $domain `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title 'DFSR backlog check skipped' `
                -WasSkipped $true -SkipReason 'GroupPolicy module not available'
            ))
        }
        $results.Add((New-CheckResult `
            -CheckId 'GPO-PARSE' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'Informational' `
            -Title 'GPO check coverage: module unavailable' `
            -IsInconclusive $true -ToolUsed 'Aggregate'
        ))
        return $results.ToArray()
    }

    # ------------------------------------------------------------------
    # AD GPOs
    # ------------------------------------------------------------------
    $adGpos = Get-ADHCAdGpos -Domain $domain
    if (-not $adGpos.Success) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-AD-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Could not query GPOs from AD' `
            -Description 'Get-GPO failed.' `
            -Evidence @{ Error = $adGpos.Error } `
            -IsInconclusive $true -ToolUsed 'Get-GPO'
        ))
        return $results.ToArray()
    }

    $adIndex = @{}
    foreach ($g in $adGpos.Gpos) { $adIndex[$g.Id] = $g }
    $adCount = $adGpos.Gpos.Count

    # ------------------------------------------------------------------
    # SYSVOL Policy folders (per DC)
    # ------------------------------------------------------------------
    $allSysvolFolders = @{}
    $sysvolFailedDcs = [System.Collections.Generic.List[string]]::new()
    $sysvolLastError = $null
    $sysvolCheckedDcs = [System.Collections.Generic.List[string]]::new()

    foreach ($dc in $dcs) {
        $sysvol = Get-ADHCSysvolPolicyFolders -DcFqdn $dc.Fqdn -Domain $domain
        if (-not $sysvol.Success) {
            $sysvolFailedDcs.Add($dc.Fqdn)
            $sysvolLastError = $sysvol.Error
            continue
        }
        $sysvolCheckedDcs.Add($dc.Fqdn)
        foreach ($f in $sysvol.Folders) {
            if (-not $allSysvolFolders.ContainsKey($f.Guid)) {
                $allSysvolFolders[$f.Guid] = [System.Collections.Generic.List[string]]::new()
            }
            $allSysvolFolders[$f.Guid].Add($dc.Fqdn)
        }
    }

    # GPO-SYSVOL-ACCESS
    if ($sysvolCheckedDcs.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ACCESS' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'FAIL' -Severity 'High' `
            -Title 'SYSVOL\Policies not accessible on any DC' `
            -Description 'Could not enumerate the Policies folder on any DC.' `
            -Evidence @{ FailedDcs = @($sysvolFailedDcs); LastError = $sysvolLastError } `
            -PotentialImpact 'Clients cannot read GPO content from SYSVOL.' `
            -PossibleCauses @('SYSVOL not shared','Permissions issue','Network path blocked') `
            -RecommendedInvestigation @('Verify SYSVOL is reachable from the evaluation host.') `
            -SuggestedCommands @("Test-Path '\\$($dcs[0].Fqdn)\SYSVOL\$domain\Policies'") `
            -ToolUsed 'Get-ChildItem'
        ))
    } elseif ($sysvolFailedDcs.Count -gt 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ACCESS' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'High' `
            -Title "SYSVOL\Policies not accessible on $($sysvolFailedDcs.Count) DC(s)" `
            -Description 'Some DCs could not be enumerated.' `
            -Evidence @{ FailedDcs = @($sysvolFailedDcs); SucceededDcs = @($sysvolCheckedDcs); LastError = $sysvolLastError } `
            -PotentialImpact 'Clients targeting those DCs may fail to read GPO content.' `
            -PossibleCauses @('Network path blocked','Permissions issue on that DC') `
            -RecommendedInvestigation @('Verify SYSVOL reachability per DC.') `
            -SuggestedCommands @('Test-Path \\<DC>\SYSVOL\<domain>\Policies') `
            -ToolUsed 'Get-ChildItem'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ACCESS' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'PASS' -Severity 'High' `
            -Title "SYSVOL\Policies accessible on all $($sysvolCheckedDcs.Count) DC(s)" `
            -Description 'All DCs expose the Policies folder.' `
            -Evidence @{ CheckedDcs = @($sysvolCheckedDcs) } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Get-ChildItem'
        ))
    }

    # ------------------------------------------------------------------
    # GPO-CNTFS-READY
    # ------------------------------------------------------------------
    $sysvolFolderCount = $allSysvolFolders.Count
    if ($sysvolFolderCount -gt 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-CNTFS-READY' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Informational' `
            -Title "Policies folder contains $sysvolFolderCount GPO folder(s)" `
            -Description 'At least one GPO folder exists in SYSVOL\Policies.' `
            -Evidence @{ FolderCount = $sysvolFolderCount } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Get-ChildItem'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-CNTFS-READY' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'Policies folder is empty' `
            -Description 'No GPO folders found in SYSVOL\Policies.' `
            -Evidence @{ FolderCount = 0 } `
            -PotentialImpact 'No impact if no GPOs have ever been created.' `
            -ToolUsed 'Get-ChildItem'
        ))
    }

    # ------------------------------------------------------------------
    # GPO-COUNT-MATCH
    # ------------------------------------------------------------------
    $results.Add((New-CheckResult `
        -CheckId 'GPO-COUNT-MATCH' -Category 'GroupPolicy' `
        -Domain $domain `
        -Status 'INFO' -Severity 'Informational' `
        -Title "GPO count: AD=$adCount, SYSVOL=$sysvolFolderCount" `
        -Description 'Informational comparison of GPO counts between AD and SYSVOL.' `
        -Evidence @{ AdCount = $adCount; SysvolCount = $sysvolFolderCount } `
        -PotentialImpact 'No impact.' `
        -ToolUsed 'Aggregate'
    ))

    # ------------------------------------------------------------------
    # GPO-SYSVOL-ORPHAN (folders in SYSVOL without AD object)
    # ------------------------------------------------------------------
    $sysvolOrphans = @()
    foreach ($guid in $allSysvolFolders.Keys) {
        if (-not $adIndex.ContainsKey($guid)) { $sysvolOrphans += $guid }
    }

    if ($sysvolFolderCount -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'No SYSVOL folders to evaluate' `
            -Evidence @{ Count = 0 } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    } elseif ($sysvolOrphans.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title 'No orphan folders in SYSVOL\Policies' `
            -Description 'Every SYSVOL folder has a matching AD GPO.' `
            -Evidence @{ Count = $sysvolFolderCount } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-SYSVOL-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title "$($sysvolOrphans.Count) orphan folder(s) in SYSVOL\Policies" `
            -Description 'SYSVOL folders without a matching AD GPO. Frequently leftover from deleted GPOs.' `
            -Evidence @{ Orphans = $sysvolOrphans; Total = $sysvolFolderCount } `
            -PotentialImpact 'No direct functional impact; cleanup is recommended.' `
            -PossibleCauses @('GPO deleted without cleaning SYSVOL','Replication delay','Permissions issue reading AD GPOs') `
            -RecommendedInvestigation @('Compare folder GUIDs with Get-GPO -All before cleanup.') `
            -SuggestedCommands @('Get-GPO -All','Get-ChildItem \\<DC>\SYSVOL\<domain>\Policies') `
            -ToolUsed 'Aggregate'
        ))
    }

    # ------------------------------------------------------------------
    # GPO-AD-ORPHAN (AD GPO without SYSVOL folder)
    # ------------------------------------------------------------------
    $adOrphans = @()
    if ($sysvolFolderCount -gt 0) {
        foreach ($guid in $adIndex.Keys) {
            if (-not $allSysvolFolders.ContainsKey($guid)) {
                $g = $adIndex[$guid]
                $adOrphans += [PSCustomObject]@{
                    Guid        = $guid
                    DisplayName = $g.DisplayName
                }
            }
        }
    }

    if ($sysvolFolderCount -eq 0 -and $adCount -gt 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-AD-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Cannot evaluate AD orphan GPOs (SYSVOL empty or unreachable)' `
            -Description 'SYSVOL was not enumerated; comparison cannot be performed.' `
            -Evidence @{ AdCount = $adCount; SysvolCount = $sysvolFolderCount } `
            -IsInconclusive $true -ToolUsed 'Aggregate'
        ))
    } elseif ($adOrphans.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-AD-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'PASS' -Severity 'High' `
            -Title 'No AD GPOs missing from SYSVOL' `
            -Description 'Every AD GPO has a matching folder in SYSVOL.' `
            -Evidence @{ Count = $adCount } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-AD-ORPHAN' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'FAIL' -Severity 'High' `
            -Title "$($adOrphans.Count) AD GPO(s) missing from SYSVOL" `
            -Description 'These GPOs exist in AD but have no matching SYSVOL folder; they will fail to apply.' `
            -Evidence @{ Orphans = $adOrphans; Total = $adCount } `
            -PotentialImpact 'Clients using these GPOs will fail GPO processing.' `
            -PossibleCauses @('SYSVOL replication lag','Recent GPO creation not yet replicated','SYSVOL corruption','Permissions issue reading SYSVOL') `
            -RecommendedInvestigation @('Verify SYSVOL replication health before any corrective action.') `
            -SuggestedCommands @('Get-GPO -All','Get-ChildItem \\<DC>\SYSVOL\<domain>\Policies') `
            -ToolUsed 'Aggregate'
        ))
    }

    # ------------------------------------------------------------------
    # GPO-DEFAULT-POLICIES
    # ------------------------------------------------------------------
    $missingDefaults = @()
    $presentDefaults = @()
    foreach ($friendly in $script:ADHCDefaultGpoGuids.Keys) {
        $guid = $script:ADHCDefaultGpoGuids[$friendly]
        if ($adIndex.ContainsKey($guid)) {
            $presentDefaults += $friendly
        } else {
            $missingDefaults += $friendly
        }
    }

    if ($missingDefaults.Count -eq 0) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-DEFAULT-POLICIES' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'PASS' -Severity 'Medium' `
            -Title 'Default domain policies are present' `
            -Description 'Both Default Domain Policy and Default Domain Controllers Policy exist.' `
            -Evidence @{ Present = $presentDefaults } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-DEFAULT-POLICIES' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'WARNING' -Severity 'Medium' `
            -Title "Missing $($missingDefaults.Count) default GPO(s)" `
            -Description 'One or more default GPOs are absent. Detected by GUID, not by name.' `
            -Evidence @{ Missing = $missingDefaults; Present = $presentDefaults; TotalAdGpos = $adCount } `
            -PotentialImpact 'Password, lockout, and DC policies may not be enforced.' `
            -PossibleCauses @('Default GPO accidentally deleted','Domain was upgraded from a template') `
            -RecommendedInvestigation @('Confirm whether defaults were intentionally removed.') `
            -SuggestedCommands @('Get-GPO -All','Get-GPO -Guid 31b2f340-016d-11d2-945f-00c04fb984f9') `
            -ToolUsed 'Aggregate'
        ))
    }

    # ------------------------------------------------------------------
    # GPO-DFSR-BACKLOG
    # ------------------------------------------------------------------
    if ($dcCount -le 1) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-DFSR-BACKLOG' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'DFSR backlog check not applicable (single-DC domain)' `
            -Evidence @{ DomainDcCount = $dcCount } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    } elseif (-not (Get-Command Get-DfsrBacklog -ErrorAction SilentlyContinue)) {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-DFSR-BACKLOG' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'DFSR backlog check skipped' `
            -Description 'Get-DfsrBacklog cmdlet is not available on this host.' `
            -WasSkipped $true -SkipReason 'DFSR module not available'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'GPO-DFSR-BACKLOG' -Category 'GroupPolicy' `
            -Domain $domain `
            -Status 'INFO' -Severity 'Medium' `
            -Title 'DFSR backlog check pending for multi-DC environments' `
            -Description 'Placeholder for 2+ DC environments; will be enabled when a test domain is available.' `
            -WasSkipped $true -SkipReason 'Not yet validated against multi-DC environment'
        ))
    }

    # ------------------------------------------------------------------
    # Coverage marker
    # ------------------------------------------------------------------
    $unknownCount = 0
    foreach ($r in $results) {
        if ($r.Status -eq 'UNKNOWN' -and $r.CheckId -notlike 'GPO-DFSR-BACKLOG') { $unknownCount++ }
    }
    $coverageOk = ($unknownCount -eq 0)
    $coverageStatus = 'UNKNOWN'
    if ($coverageOk) { $coverageStatus = 'PASS' }

    $results.Add((New-CheckResult `
        -CheckId 'GPO-PARSE' -Category 'GroupPolicy' `
        -Domain $domain `
        -Status $coverageStatus -Severity 'Informational' `
        -Title 'GPO check coverage' `
        -Description 'Reports whether all GPO checks produced a definitive result.' `
        -Evidence @{ AdGpoCount = $adCount; SysvolFolderCount = $sysvolFolderCount; UnknownChecks = $unknownCount } `
        -IsInconclusive (-not $coverageOk) `
        -ToolUsed 'Aggregate'
    ))

    $results.ToArray()
}

#endregion