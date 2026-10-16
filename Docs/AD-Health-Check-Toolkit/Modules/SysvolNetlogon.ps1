Set-StrictMode -Version Latest

function ConvertTo-ADHCServiceSnapshot {
    <#
    .SYNOPSIS
        Converts a ServiceController into a plain object with string Status
        and StartType so Evidence renders as "Running" / "Automatic" instead
        of the raw enum integers.
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Service)
    if (-not $Service) { return $null }
    $statusText = $null
    if ($Service.Status)    { $statusText = $Service.Status.ToString() }
    $startText  = $null
    if ($Service.StartType) { $startText  = $Service.StartType.ToString() }
    [PSCustomObject]@{
        Name      = $Service.Name
        Status    = $statusText
        StartType = $startText
    }
}

function Get-ADHCSmbShareState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string[]]$ShareNames,
        [PSCredential]$Credential
    )

    if (Test-ADHCIsLocalhost -ComputerName $ComputerName) {
        try {
            $shares = Get-SmbShare -Name $ShareNames -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Success=$true; Method='Local'; Shares=$shares; Error=$null }
        } catch {
            return [PSCustomObject]@{ Success=$false; Method='Local'; Shares=@(); Error=$_.Exception.Message }
        }
    }

    $remote = Invoke-ADHCRemote -ComputerName $ComputerName -TimeoutSeconds 30 -Credential $Credential `
        -ScriptBlock {
            param($names)
            Get-SmbShare -Name $names -ErrorAction SilentlyContinue |
                Select-Object Name, Path, Description
        } -ArgumentList @(,$ShareNames)

    if ($remote.Success) {
        return [PSCustomObject]@{ Success=$true; Method='WinRM'; Shares=$remote.Output; Error=$null }
    }
    return [PSCustomObject]@{ Success=$false; Method='WinRM'; Shares=@(); Error=$remote.Error }
}

function Test-ADHCUncPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UncPath,
        [int]$TimeoutMs = 5000
    )
    try {
        $job = Start-Job -ScriptBlock {
            param($p)
            Test-Path -LiteralPath $p -ErrorAction Stop
        } -ArgumentList $UncPath

        $done = Wait-Job -Job $job -Timeout ([int]($TimeoutMs / 1000))
        if (-not $done) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Exists=$false; TimedOut=$true; Error='Timeout' }
        }
        $res = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Exists=[bool]$res; TimedOut=$false; Error=$null }
    } catch {
        return [PSCustomObject]@{ Exists=$false; TimedOut=$false; Error=$_.Exception.Message }
    }
}

function Invoke-ADHCSysvolNetlogon {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $domain = $Context.Domain
    $results = [System.Collections.Generic.List[object]]::new()
    $dcCount = @($Context.DomainControllers).Count

    Write-ADHCLog -Level Info -Message "SYSVOL/NETLOGON: evaluating $domain (dcCount=$dcCount)" -Logger $Context.Logger

    foreach ($dc in $Context.DomainControllers) {
        Write-ADHCLog -Level Info -Message "SYSVOL/NETLOGON: evaluating $($dc.Fqdn)" -Logger $Context.Logger
        $dcSw = [System.Diagnostics.Stopwatch]::StartNew()

        # --------------------------------------------------------------
        # 1) Shares SYSVOL and NETLOGON
        # --------------------------------------------------------------
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $shareProbe = Get-ADHCSmbShareState -ComputerName $dc.Fqdn -ShareNames @('SYSVOL','NETLOGON') -Credential $Context.Credential
        $sw.Stop()

        if (-not $shareProbe.Success) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-QUERY' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "Could not enumerate shares on $($dc.Fqdn)" `
                -Description 'Get-SmbShare via local or WinRM failed.' `
                -Evidence @{ Error = $shareProbe.Error; Method = $shareProbe.Method } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-SmbShare'
            ))
        } else {
            $names = @{}
            foreach ($s in $shareProbe.Shares) {
                if ($s -and $s.Name) { $names[$s.Name.ToUpperInvariant()] = $s }
            }

            foreach ($required in @('SYSVOL','NETLOGON')) {
                if ($names.ContainsKey($required)) {
                    $results.Add((New-CheckResult `
                        -CheckId ("SYSVOL-SHARE-{0}" -f $required) -Category 'SYSVOL' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'PASS' -Severity 'High' `
                        -Title "Share $required present on $($dc.Fqdn)" `
                        -Description "Share $required exists." `
                        -Evidence @{ Share = $required; Path = $names[$required].Path; Method = $shareProbe.Method } `
                        -PotentialImpact 'No impact.' `
                        -SuggestedCommands @("Get-SmbShare -Name $required") `
                        -Duration $sw.Elapsed -ToolUsed 'Get-SmbShare'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId ("SYSVOL-SHARE-{0}" -f $required) -Category 'SYSVOL' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'FAIL' -Severity 'High' `
                        -Title "Share $required missing on $($dc.Fqdn)" `
                        -Description "Share $required was not found." `
                        -Evidence @{ Share = $required; Found = $false; Method = $shareProbe.Method } `
                        -PotentialImpact "$required is required for GPO processing and logon scripts." `
                        -PossibleCauses @('SYSVOL not shared','Netlogon service issue','Share deleted accidentally') `
                        -RecommendedInvestigation @('Check SYSVOL replication state and Netlogon service.') `
                        -SuggestedCommands @(
                            "net share $required",
                            "Get-SmbShare -Name $required",
                            "dcdiag /test:netlogons"
                        ) `
                        -Duration $sw.Elapsed -ToolUsed 'Get-SmbShare'
                    ))
                }
            }
        }

        # --------------------------------------------------------------
        # 2) UNC paths: \\DC\SYSVOL\<domain> and ...\Policies
        # --------------------------------------------------------------
        $domainUnc   = "\\$($dc.Fqdn)\SYSVOL\$domain"
        $policiesUnc = "$domainUnc\Policies"

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $dPath = Test-ADHCUncPath -UncPath $domainUnc
        $sw.Stop()

        if ($dPath.Exists) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-PATH-DOMAIN' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'PASS' -Severity 'High' `
                -Title "SYSVOL domain path accessible on $($dc.Fqdn)" `
                -Description "UNC path $domainUnc is reachable." `
                -Evidence @{ UncPath = $domainUnc; Exists = $true } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @("Test-Path '$domainUnc'") `
                -Duration $sw.Elapsed -ToolUsed 'Test-Path'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-PATH-DOMAIN' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'FAIL' -Severity 'High' `
                -Title "SYSVOL domain path NOT accessible on $($dc.Fqdn)" `
                -Description "UNC path $domainUnc is not reachable." `
                -Evidence @{ UncPath = $domainUnc; Exists = $false; TimedOut = $dPath.TimedOut; Error = $dPath.Error } `
                -PotentialImpact 'Clients cannot read GPO files from this DC.' `
                -PossibleCauses @('SYSVOL not shared','DFS Replication not initialized','Permission issue') `
                -RecommendedInvestigation @('Check SYSVOL share and DFSR state on this DC.') `
                -SuggestedCommands @(
                    "Test-Path '$domainUnc'",
                    "dcdiag /test:sysvolcheck"
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Test-Path'
            ))
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $pPath = Test-ADHCUncPath -UncPath $policiesUnc
        $sw.Stop()

        if ($pPath.Exists) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-PATH-POLICIES' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'PASS' -Severity 'High' `
                -Title "SYSVOL Policies path accessible on $($dc.Fqdn)" `
                -Description "UNC path $policiesUnc is reachable." `
                -Evidence @{ UncPath = $policiesUnc; Exists = $true } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @("Test-Path '$policiesUnc'") `
                -Duration $sw.Elapsed -ToolUsed 'Test-Path'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-PATH-POLICIES' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'FAIL' -Severity 'High' `
                -Title "SYSVOL Policies path NOT accessible on $($dc.Fqdn)" `
                -Description "UNC path $policiesUnc is not reachable." `
                -Evidence @{ UncPath = $policiesUnc; Exists = $false; TimedOut = $pPath.TimedOut; Error = $pPath.Error } `
                -PotentialImpact 'Group Policy processing will fail for clients using this DC.' `
                -PossibleCauses @('SYSVOL incomplete','DFSR not initialized','Permission issue') `
                -RecommendedInvestigation @('Compare Policies folder with another DC, if any.') `
                -SuggestedCommands @(
                    "Test-Path '$policiesUnc'",
                    "dcdiag /test:sysvolcheck"
                ) `
                -Duration $sw.Elapsed -ToolUsed 'Test-Path'
            ))
        }

        # --------------------------------------------------------------
        # 3) DFSR state (SYSVOL backend)
        # --------------------------------------------------------------
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $isLocal = Test-ADHCIsLocalhost -ComputerName $dc.Fqdn

        $dfsrState = $null
        $dfsrError = $null
        $frsState  = $null

        if ($isLocal) {
            try {
                $dfsrState = Get-Service -Name 'DFSR' -ErrorAction Stop
            } catch { $dfsrError = $_.Exception.Message }

            try {
                $frsState = Get-Service -Name 'FRS' -ErrorAction SilentlyContinue
            } catch { }
        } else {
            $rem = Invoke-ADHCRemote -ComputerName $dc.Fqdn -TimeoutSeconds 30 -Credential $Context.Credential `
                -ScriptBlock {
                    $dfsr = $null; $frs = $null
                    try { $dfsr = Get-Service -Name 'DFSR' -ErrorAction Stop | Select-Object Name, Status, StartType } catch { }
                    try { $frs  = Get-Service -Name 'FRS'  -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType } catch { }
                    [PSCustomObject]@{ Dfsr = $dfsr; Frs = $frs }
                }
            if ($rem.Success) {
                $dfsrState = $rem.Output.Dfsr
                $frsState  = $rem.Output.Frs
            } else {
                $dfsrError = $rem.Error
            }
        }
        $sw.Stop()

        if ($dfsrError -and -not $dfsrState) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-DFSR-STATE' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title "DFSR state could not be queried on $($dc.Fqdn)" `
                -Description 'Neither local nor remote service query succeeded.' `
                -Evidence @{ Error = $dfsrError; IsLocal = $isLocal } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-Service'
            ))
        } else {
            $dfsrRunning = ($dfsrState -and $dfsrState.Status -eq 'Running')
            $frsPresent  = [bool]$frsState

            if ($dfsrRunning -and -not $frsPresent) {
                $results.Add((New-CheckResult `
                    -CheckId 'SYSVOL-DFSR-STATE' -Category 'SYSVOL' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'PASS' -Severity 'High' `
                    -Title "SYSVOL uses DFSR on $($dc.Fqdn)" `
                    -Description 'DFSR is running and FRS is not installed.' `
                    -Evidence @{ DFSR = (ConvertTo-ADHCServiceSnapshot -Service $dfsrState); FRSPresent = $false } `
                    -PotentialImpact 'No impact.' `
                    -SuggestedCommands @('Get-Service DFSR','dfsrmig /getmigrationstate') `
                    -Duration $sw.Elapsed -ToolUsed 'Get-Service'
                ))
            } elseif ($frsPresent) {
                $results.Add((New-CheckResult `
                    -CheckId 'SYSVOL-DFSR-STATE' -Category 'SYSVOL' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'WARNING' -Severity 'High' `
                    -Title "FRS service present on $($dc.Fqdn)" `
                    -Description 'FRS should not be present in modern domains; SYSVOL should use DFSR.' `
                    -Evidence @{ DFSR = (ConvertTo-ADHCServiceSnapshot -Service $dfsrState); FRS = (ConvertTo-ADHCServiceSnapshot -Service $frsState) } `
                    -PotentialImpact 'Legacy FRS is deprecated and unsupported for SYSVOL on modern Windows Server.' `
                    -PossibleCauses @('Domain was migrated from Windows Server 2003/2008 without DFSR migration','FRS role remained installed') `
                    -RecommendedInvestigation @('Check DFSR migration state of the domain.') `
                    -SuggestedCommands @('dfsrmig /getmigrationstate') `
                    -Duration $sw.Elapsed -ToolUsed 'Get-Service'
                ))
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'SYSVOL-DFSR-STATE' -Category 'SYSVOL' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'FAIL' -Severity 'High' `
                    -Title "DFSR service not running on $($dc.Fqdn)" `
                    -Description 'The DFSR service is not running; SYSVOL replication is broken.' `
                    -Evidence @{ DFSR = (ConvertTo-ADHCServiceSnapshot -Service $dfsrState); FRSPresent = $frsPresent } `
                    -PotentialImpact 'SYSVOL will not replicate to/from this DC; GPOs may not be updated.' `
                    -PossibleCauses @('Service stopped','Startup failure','Role removed') `
                    -RecommendedInvestigation @('Start the DFSR service and check DFS Replication event log.') `
                    -SuggestedCommands @('Start-Service DFSR','Get-WinEvent -LogName "DFS Replication" -MaxEvents 20') `
                    -Duration $sw.Elapsed -ToolUsed 'Get-Service'
                ))
            }
        }

        # --------------------------------------------------------------
        # 4) NETLOGON content (informational)
        # --------------------------------------------------------------
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $netlogonUnc = "\\$($dc.Fqdn)\NETLOGON"
        $netlogonContent = $null
        $netlogonErr = $null
        try {
            $job = Start-Job -ScriptBlock {
                param($p)
                Get-ChildItem -LiteralPath $p -ErrorAction Stop |
                    Select-Object -First 5 -ExpandProperty Name
            } -ArgumentList $netlogonUnc
            $done = Wait-Job -Job $job -Timeout 5
            if ($done) {
                $netlogonContent = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            } else {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                $netlogonErr = 'Timeout listing NETLOGON content'
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        } catch {
            $netlogonErr = $_.Exception.Message
        }
        $sw.Stop()

        if ($netlogonErr) {
            $results.Add((New-CheckResult `
                -CheckId 'NETLOGON-SHARE-CONTENT' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Informational' `
                -Title "NETLOGON content not enumerated on $($dc.Fqdn)" `
                -Description 'Could not list NETLOGON contents.' `
                -Evidence @{ Error = $netlogonErr; UncPath = $netlogonUnc } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ChildItem'
            ))
        } else {
            $count = @($netlogonContent).Count
            if ($count -gt 0) {
                $title = "NETLOGON has content on $($dc.Fqdn) ($count item(s))"
                $desc  = 'Logon scripts or other files are present in NETLOGON.'
            } else {
                $title = "NETLOGON is empty on $($dc.Fqdn)"
                $desc  = 'No files found in NETLOGON. This is common in modern domains using only GPOs.'
            }
            $results.Add((New-CheckResult `
                -CheckId 'NETLOGON-SHARE-CONTENT' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'INFO' -Severity 'Informational' `
                -Title $title `
                -Description $desc `
                -Evidence @{ UncPath = $netlogonUnc; ItemCount = $count; Sample = $netlogonContent } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @("Get-ChildItem '$netlogonUnc'") `
                -Duration $sw.Elapsed -ToolUsed 'Get-ChildItem'
            ))
        }

        # --------------------------------------------------------------
        # 5) DFSR backlog (multi-DC only, needs Get-DfsrBacklog)
        # --------------------------------------------------------------
        if ($dcCount -le 1) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-DFSR-BACKLOG' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'INFO' -Severity 'Informational' `
                -Title 'DFSR backlog check not applicable (single-DC domain)' `
                -Description 'Backlog is only meaningful with 2+ DCs.' `
                -Evidence @{ DomainDcCount = $dcCount } `
                -PotentialImpact 'No impact.' `
                -Duration $dcSw.Elapsed -ToolUsed 'Aggregate'
            ))
        } elseif (-not (Get-Command Get-DfsrBacklog -ErrorAction SilentlyContinue)) {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-DFSR-BACKLOG' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title 'DFSR backlog check skipped' `
                -Description 'Get-DfsrBacklog cmdlet not available (needs RSAT-DFS-Mgmt-Con / DFSR module).' `
                -WasSkipped $true -SkipReason 'Get-DfsrBacklog not available'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'SYSVOL-DFSR-BACKLOG' -Category 'SYSVOL' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title 'DFSR backlog check pending implementation for 2-DC environments' `
                -Description 'Placeholder: will be evaluated in multi-DC testing.' `
                -WasSkipped $true -SkipReason 'Multi-DC path not yet validated'
            ))
        }

        $dcSw.Stop()
        Write-ADHCLog -Level Info -Message "SYSVOL/NETLOGON: done for $($dc.Fqdn) in $($dcSw.Elapsed.TotalSeconds.ToString('F1'))s" -Logger $Context.Logger
    }

    $results.ToArray()
}