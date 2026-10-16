Set-StrictMode -Version Latest

#region --- Parser: repadmin /replsummary (pt-BR / en-US) ---

function ConvertFrom-ADHCRepadminReplsummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed          = $false
        OutboundHeader  = $false
        InboundHeader   = $false
        Outbound        = @()
        Inbound         = @()
        Notes           = @()
    }

    if (-not $RawOutput) { return $result }

    $lines = $RawOutput -split "`r?`n"

    $deltaRx = '\d+[dhms](?::\d+[dhms])*'
    $section = $null

    foreach ($line in $lines) {
        if ($null -eq $line) { continue }
        $trim = $line.TrimEnd()

        if ($trim -match '^\s*(DSA\s+Origem|Source\s+DSA)') {
            $section = 'Outbound'
            $result.OutboundHeader = $true
            continue
        }
        if ($trim -match '^\s*(DSA\s+Destino|Destination\s+DSA)') {
            $section = 'Inbound'
            $result.InboundHeader = $true
            continue
        }

        if (-not $section) { continue }
        if ($trim -match '^\s*$') { continue }

        $m = [regex]::Match($trim, "^\s*(\S+)\s+($deltaRx)\s+(\d+)\s*/\s*(\d+)\s+(\d+)\s*(.*)$")
        if (-not $m.Success) { continue }

        $row = [PSCustomObject]@{
            Dc        = $m.Groups[1].Value
            Delta     = $m.Groups[2].Value
            Fails     = [int]$m.Groups[3].Value
            Total     = [int]$m.Groups[4].Value
            Percent   = [int]$m.Groups[5].Value
            LastError = ($m.Groups[6].Value).Trim()
        }

        if ($section -eq 'Outbound') { $result.Outbound += $row }
        else                         { $result.Inbound  += $row }
    }

    if ($result.OutboundHeader -or $result.InboundHeader) {
        $result.Parsed = $true
    } else {
        $result.Notes += 'Neither "DSA Origem/Source DSA" nor "DSA Destino/Destination DSA" header found.'
    }

    $result
}

#endregion

#region --- Helpers ---

function ConvertFrom-ADHCReplDelta {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Delta)

    if (-not $Delta) { return $null }
    $days = 0; $hours = 0; $minutes = 0; $seconds = 0
    foreach ($part in $Delta -split ':') {
        if     ($part -match '^(\d+)d$') { $days    = [int]$Matches[1] }
        elseif ($part -match '^(\d+)h$') { $hours   = [int]$Matches[1] }
        elseif ($part -match '^(\d+)m$') { $minutes = [int]$Matches[1] }
        elseif ($part -match '^(\d+)s$') { $seconds = [int]$Matches[1] }
        else { return $null }
    }
    return (New-TimeSpan -Days $days -Hours $hours -Minutes $minutes -Seconds $seconds)
}

function Get-ADHCRepadminReplsummaryRaw {
    [CmdletBinding()]
    param([int]$TimeoutSeconds = 60)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = $tmpOut + '.err'

    try {
        $p = Start-Process -FilePath 'repadmin.exe' `
            -ArgumentList @('/replsummary') `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr `
            -ErrorAction Stop

        # repadmin.exe writes to the OEM code page (CP-850 on Windows pt-BR).
        $oemEnc = [System.Text.Encoding]::GetEncoding([int][System.Text.Encoding]::Default.CodePage)
        if ([System.Text.Encoding]::Default.CodePage -eq 1252) {
            $oemEnc = [System.Text.Encoding]::GetEncoding(850)
        }

        $stdout = $null
        $stderr = $null
        if (Test-Path -LiteralPath $tmpOut) {
            $bytesOut = [System.IO.File]::ReadAllBytes($tmpOut)
            $stdout = $oemEnc.GetString($bytesOut)
        }
        if (Test-Path -LiteralPath $tmpErr) {
            $bytesErr = [System.IO.File]::ReadAllBytes($tmpErr)
            $stderr = $oemEnc.GetString($bytesErr)
        }

        [PSCustomObject]@{
            Success  = $true
            ExitCode = $p.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
            Duration = $sw.Elapsed
            Error    = $null
        }
    } catch {
        [PSCustomObject]@{
            Success  = $false
            ExitCode = $null
            StdOut   = $null
            StdErr   = $null
            Duration = $sw.Elapsed
            Error    = $_.Exception.Message
        }
    } finally {
        Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
        $sw.Stop()
    }
}

function Get-ADHCReplicationFailureForSelf {
    [CmdletBinding()]
    param()
    try {
        $rows = Get-ADReplicationFailure -Target $env:COMPUTERNAME -Scope Server -ErrorAction Stop
        [PSCustomObject]@{ Success=$true; Rows=@($rows); Error=$null }
    } catch {
        [PSCustomObject]@{ Success=$false; Rows=@(); Error=$_.Exception.Message }
    }
}

function Get-ADHCReplicationPartnerMetadataForSelf {
    [CmdletBinding()]
    param()
    try {
        $rows = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -Scope Server -PartnerType Both -ErrorAction Stop
        [PSCustomObject]@{ Success=$true; Rows=@($rows); Error=$null }
    } catch {
        [PSCustomObject]@{ Success=$false; Rows=@(); Error=$_.Exception.Message }
    }
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCReplication {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $defaults = Get-ADHCDefaults
    $cfg      = $defaults.Replication
    $domain   = $Context.Domain
    $dcCount  = @($Context.DomainControllers).Count
    $localDc  = $env:COMPUTERNAME

    $results = [System.Collections.Generic.List[object]]::new()

    Write-ADHCLog -Level Info -Message "Replication: domain=$domain dcCount=$dcCount localDc=$localDc" -Logger $Context.Logger

    # ------------------------------------------------------------------
    # 0) Capability probe
    # ------------------------------------------------------------------
    $cmds    = @('Get-ADReplicationFailure','Get-ADReplicationPartnerMetadata','Get-ADReplicationSiteLink')
    $missing = @($cmds | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    $adReplAvailable = ($missing.Count -eq 0)

    if ($adReplAvailable) {
        $capStatus = 'PASS'
        $capSev    = 'Informational'
        $capImpact = 'No impact.'
    } else {
        $capStatus = 'WARNING'
        $capSev    = 'Medium'
        $capImpact = 'Replication checks degrade to repadmin evidence only.'
    }

    $results.Add((New-CheckResult `
        -CheckId 'REPL-CMDLET-AVAILABLE' -Category 'Replication' `
        -Domain $domain `
        -Status $capStatus -Severity $capSev `
        -Title 'AD replication cmdlets availability' `
        -Description 'Checks that Get-ADReplication* cmdlets are present.' `
        -Evidence @{ Available = $adReplAvailable; Missing = $missing } `
        -PotentialImpact $capImpact `
        -PossibleCauses @('RSAT-AD-PowerShell not installed','Module not imported') `
        -RecommendedInvestigation @('Install RSAT-AD-PowerShell if any cmdlet is missing.') `
        -SuggestedCommands @('Get-Command Get-ADReplicationFailure, Get-ADReplicationPartnerMetadata') `
        -ToolUsed 'Get-Command'
    ))

    # ------------------------------------------------------------------
    # 1) REPL-FAILURE
    # ------------------------------------------------------------------
    if ($adReplAvailable) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fr = Get-ADHCReplicationFailureForSelf
        $sw.Stop()

        if (-not $fr.Success) {
            $results.Add((New-CheckResult `
                -CheckId 'REPL-FAILURE' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title 'Replication failures could not be queried' `
                -Description 'Get-ADReplicationFailure failed on the local DC.' `
                -Evidence @{ Error = $fr.Error; Target = $localDc; Scope = 'Server' } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationFailure'
            ))
        } else {
            $rows = $fr.Rows
            if ($rows.Count -eq 0) {
                $results.Add((New-CheckResult `
                    -CheckId 'REPL-FAILURE' -Category 'Replication' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'PASS' -Severity 'High' `
                    -Title "No replication failures reported by $localDc" `
                    -Description 'Get-ADReplicationFailure returned no failing partners from this DC.' `
                    -Evidence @{ PartnerCount = 0; DomainDcCount = $dcCount } `
                    -PotentialImpact 'No impact.' `
                    -SuggestedCommands @("repadmin /showrepl $env:COMPUTERNAME") `
                    -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationFailure'
                ))
            } else {
                foreach ($r in $rows) {
                    $fc = 0
                    if ($null -ne $r.FailureCount) { $fc = [int]$r.FailureCount }

                    $lastSuccessDays = $null
                    if ($r.LastSuccessTime) {
                        $lastSuccessDays = ((Get-Date).ToUniversalTime() - $r.LastSuccessTime.ToUniversalTime()).TotalDays
                    }

                    $ev = @{
                        Partner          = $r.Partner
                        Server           = $r.Server
                        FailureCount     = $fc
                        FirstFailureTime = $r.FirstFailureTime
                        LastFailureTime  = $r.LastFailureTime
                        LastSuccessTime  = $r.LastSuccessTime
                        LastSuccessDays  = $lastSuccessDays
                        LastError        = $r.LastError
                    }
                    $sevInfo = Get-ADHCSeverity -CheckId 'REPL-FAILURE' -Status 'FAIL' -Evidence $ev

                    $results.Add((New-CheckResult `
                        -CheckId ("REPL-FAILURE-{0}" -f ($r.Partner -replace '[^A-Za-z0-9]','-')) -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $r.Server `
                        -Status 'FAIL' -Severity $sevInfo.Severity `
                        -Title ("Replication failing to {0}" -f $r.Partner) `
                        -Description 'Get-ADReplicationFailure reported failures with this partner.' `
                        -Evidence $ev `
                        -PotentialImpact 'Directory divergence and stale authentication data on affected partitions.' `
                        -PossibleCauses @('DNS resolution failure','RPC blocked','Kerberos issue','Network path','Firewall','Target DC down') `
                        -RecommendedInvestigation @('Resolve DNS for the partner','Test RPC ports 135/49152+','Check System and Directory Service logs on both sides') `
                        -SuggestedCommands @(
                            "repadmin /showrepl $env:COMPUTERNAME",
                            "repadmin /replsum /errorsonly"
                        ) `
                        -ErrorCode ([string]$r.LastError) `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationFailure'
                    ))
                }
            }
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'REPL-FAILURE' -Category 'Replication' `
            -Domain $domain -DomainController $localDc `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Replication failures check skipped (cmdlets unavailable)' `
            -Description 'Get-ADReplicationFailure cmdlet not available on this host.' `
            -Evidence @{ Missing = $missing } `
            -WasSkipped $true -SkipReason 'Get-ADReplication* cmdlets not available'
        ))
    }

    # ------------------------------------------------------------------
    # 2) REPL-LAST-SUCCESS + REPL-PARTNER-COUNT
    # ------------------------------------------------------------------
    if ($adReplAvailable) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $pm = Get-ADHCReplicationPartnerMetadataForSelf
        $sw.Stop()

        if (-not $pm.Success) {
            $results.Add((New-CheckResult `
                -CheckId 'REPL-LAST-SUCCESS' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title 'Partner metadata could not be queried' `
                -Description 'Get-ADReplicationPartnerMetadata failed on the local DC.' `
                -Evidence @{ Error = $pm.Error } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
            ))
            $results.Add((New-CheckResult `
                -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title 'Partner count could not be determined' `
                -Description 'Get-ADReplicationPartnerMetadata failed on the local DC.' `
                -Evidence @{ Error = $pm.Error } `
                -WasSkipped $true -SkipReason 'Partner metadata unavailable'
            ))
        } else {
            $rows = $pm.Rows

            if ($rows.Count -eq 0) {
                if ($dcCount -le 1) {
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-LAST-SUCCESS' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'INFO' -Severity 'Informational' `
                        -Title 'No replication partners (single-DC domain)' `
                        -Description 'This domain has only one DC; replication does not apply.' `
                        -Evidence @{ PartnerCount = 0; DomainDcCount = $dcCount; Note = 'Single-DC domain; partner checks not applicable.' } `
                        -PotentialImpact 'No impact.' `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'INFO' -Severity 'Informational' `
                        -Title '0 replication partners (expected for a single-DC domain)' `
                        -Description 'Domain has 1 DC; no partners expected.' `
                        -Evidence @{ PartnerCount = 0; DomainDcCount = $dcCount } `
                        -PotentialImpact 'No impact.' `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-LAST-SUCCESS' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'WARNING' -Severity 'High' `
                        -Title 'No partner metadata in a multi-DC domain' `
                        -Description "Domain has $dcCount DCs but no partner metadata was returned." `
                        -Evidence @{ PartnerCount = 0; DomainDcCount = $dcCount } `
                        -PotentialImpact 'Missing connection objects or KCC did not create inbound partners.' `
                        -PossibleCauses @('KCC issue','No connection objects','Partner metadata query filtered') `
                        -RecommendedInvestigation @('Check NTDS Connection objects under each DC in ADUC or ADSIEdit.') `
                        -SuggestedCommands @("repadmin /showconn $env:COMPUTERNAME") `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'WARNING' -Severity 'Medium' `
                        -Title "0 partners with $dcCount DCs in the domain" `
                        -Description 'Expected at least one partner per partition.' `
                        -Evidence @{ PartnerCount = 0; DomainDcCount = $dcCount } `
                        -PotentialImpact 'Replication may be disabled or not scheduled.' `
                        -SuggestedCommands @("repadmin /showconn $env:COMPUTERNAME", "repadmin /kcc") `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                }
            } else {
                $uniquePartners = @($rows | ForEach-Object { $_.Partner } | Sort-Object -Unique)

                foreach ($r in $rows) {
                    $partner   = $r.Partner
                    $partition = $r.Partition
                    $lastSuccess = $r.LastReplicationSuccess
                    $hoursSince = $null
                    $daysSince  = $null
                    if ($lastSuccess) {
                        $ts = (Get-Date).ToUniversalTime() - $lastSuccess.ToUniversalTime()
                        $hoursSince = $ts.TotalHours
                        $daysSince  = $ts.TotalDays
                    }

                    $status = 'PASS'
                    if ($null -ne $daysSince) {
                        if ($daysSince -gt $cfg.StalePartnerDays) {
                            $status = 'FAIL'
                        } elseif ($daysSince -gt $cfg.WarningPartnerDays) {
                            $status = 'WARNING'
                        }
                    }

                    $ev = @{
                        Partner                 = $partner
                        Partition               = $partition
                        LastReplicationSuccess  = $lastSuccess
                        HoursSinceSuccess       = $hoursSince
                        DaysSinceSuccess        = $daysSince
                        ConsecutiveFailureCount = $r.ConsecutiveReplicationFailures
                        LastReplicationResult   = $r.LastReplicationResult
                    }
                    $sevInfo = Get-ADHCSeverity -CheckId 'REPL-LAST-SUCCESS' -Status $status -Evidence $ev

                    if ($status -eq 'PASS') {
                        $title = "Replication from $partner is current"
                    } else {
                        $title = "Replication from $partner last succeeded {0:N1}h ago" -f [double]$hoursSince
                    }

                    $impact = 'No impact.'
                    if ($status -ne 'PASS') {
                        $impact = 'Stale data on this DC; authentication and lookups may return outdated information.'
                    }

                    $results.Add((New-CheckResult `
                        -CheckId ("REPL-LAST-SUCCESS-{0}" -f ($partner -replace '[^A-Za-z0-9]','-')) -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status $status -Severity $sevInfo.Severity `
                        -Title $title `
                        -Description ("Partner: {0}; Partition: {1}; LastResult: {2}" -f $partner, $partition, $r.LastReplicationResult) `
                        -Evidence $ev `
                        -PotentialImpact $impact `
                        -PossibleCauses @('Replication failure','RPC blocked','DNS issue','Target DC offline','Schedule delay') `
                        -RecommendedInvestigation @('Check last error and consecutive failures','Compare with repadmin /showrepl') `
                        -SuggestedCommands @(
                            "repadmin /showrepl $env:COMPUTERNAME",
                            "repadmin /replsummary"
                        ) `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                }

                $expected = $dcCount - 1
                $observed = $uniquePartners.Count
                if ($observed -ge $expected) {
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'PASS' -Severity 'Informational' `
                        -Title "Replication partners as expected ($observed)" `
                        -Description "Observed $observed partner(s); domain has $dcCount DC(s)." `
                        -Evidence @{ Observed = $observed; ExpectedMinimum = $expected; Partners = $uniquePartners } `
                        -PotentialImpact 'No impact.' `
                        -SuggestedCommands @("repadmin /showrepl $env:COMPUTERNAME") `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'WARNING' -Severity 'Medium' `
                        -Title "Fewer replication partners than expected ($observed of $expected)" `
                        -Description 'The number of inbound partners is lower than the number of other DCs in the domain.' `
                        -Evidence @{ Observed = $observed; ExpectedMinimum = $expected; Partners = $uniquePartners } `
                        -PotentialImpact 'Missing connection objects may prevent replication from some DCs.' `
                        -PossibleCauses @('KCC did not create some connection objects','Manual topology change','Some DCs are RODCs') `
                        -RecommendedInvestigation @('Check NTDS Connection objects per DC','Review KCC event log') `
                        -SuggestedCommands @("repadmin /showconn $env:COMPUTERNAME", "repadmin /kcc") `
                        -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationPartnerMetadata'
                    ))
                }
            }
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'REPL-LAST-SUCCESS' -Category 'Replication' `
            -Domain $domain -DomainController $localDc `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Last-success check skipped (cmdlets unavailable)' `
            -Description 'Get-ADReplicationPartnerMetadata cmdlet not available.' `
            -WasSkipped $true -SkipReason 'Get-ADReplication* cmdlets not available'
        ))
        $results.Add((New-CheckResult `
            -CheckId 'REPL-PARTNER-COUNT' -Category 'Replication' `
            -Domain $domain -DomainController $localDc `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'Partner count check skipped (cmdlets unavailable)' `
            -WasSkipped $true -SkipReason 'Get-ADReplication* cmdlets not available'
        ))
    }

    # ------------------------------------------------------------------
    # 3) REPL-SITE-LINK
    # ------------------------------------------------------------------
    if ($adReplAvailable) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $siteLinkError = $null
        $siteLinks = @()
        try {
            $siteLinks = @(Get-ADReplicationSiteLink -Filter * -Properties InterSiteTransportProtocol, Options -ErrorAction Stop)
        } catch {
            $siteLinkError = $_.Exception.Message
        }
        $sw.Stop()

        if ($siteLinkError) {
            $results.Add((New-CheckResult `
                -CheckId 'REPL-SITE-LINK' -Category 'Replication' `
                -Domain $domain `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title 'Site links could not be enumerated' `
                -Description 'Get-ADReplicationSiteLink failed.' `
                -Evidence @{ Error = $siteLinkError } `
                -IsInconclusive $true -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationSiteLink'
            ))
        } elseif ($siteLinks.Count -eq 0) {
            $results.Add((New-CheckResult `
                -CheckId 'REPL-SITE-LINK' -Category 'Replication' `
                -Domain $domain `
                -Status 'WARNING' -Severity 'Medium' `
                -Title 'No replication site links configured' `
                -Description 'No site links were returned for this forest.' `
                -Evidence @{ Count = 0 } `
                -PotentialImpact 'Inter-site replication will not occur between distinct sites.' `
                -PossibleCauses @('Single-site forest (acceptable)','Site links deleted (problematic)') `
                -RecommendedInvestigation @('Verify if this is a single-site forest.') `
                -SuggestedCommands @('Get-ADReplicationSiteLink -Filter *') `
                -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationSiteLink'
            ))
        } else {
            $issues = @()
            foreach ($sl in $siteLinks) {
                $freq = [int]$sl.ReplicationFrequencyInMinutes
                $transport = $sl.InterSiteTransportProtocol
                if ($freq -lt $cfg.MinReplicationFrequency) {
                    $issues += "Link '$($sl.Name)' frequency $freq min is below $($cfg.MinReplicationFrequency)."
                }
                if ($freq -gt $cfg.MaxReplicationFrequency) {
                    $issues += "Link '$($sl.Name)' frequency $freq min is above $($cfg.MaxReplicationFrequency)."
                }
                if ($transport -and ($cfg.AcceptedTransports -notcontains $transport)) {
                    $issues += "Link '$($sl.Name)' transport '$transport' is not in the accepted list."
                }
            }

            if ($issues.Count -eq 0) {
                $results.Add((New-CheckResult `
                    -CheckId 'REPL-SITE-LINK' -Category 'Replication' `
                    -Domain $domain `
                    -Status 'PASS' -Severity 'Informational' `
                    -Title "Site links look healthy ($($siteLinks.Count))" `
                    -Description 'Cost, frequency and transport are within expected bounds.' `
                    -Evidence @{ SiteLinks = @($siteLinks | Select-Object Name, Cost, ReplicationFrequencyInMinutes, InterSiteTransportProtocol) } `
                    -PotentialImpact 'No impact.' `
                    -SuggestedCommands @('Get-ADReplicationSiteLink -Filter * -Properties *') `
                    -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationSiteLink'
                ))
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'REPL-SITE-LINK' -Category 'Replication' `
                    -Domain $domain `
                    -Status 'WARNING' -Severity 'Medium' `
                    -Title 'Site link configuration looks unusual' `
                    -Description 'One or more site links fall outside the expected range.' `
                    -Evidence @{
                        Issues    = $issues
                        SiteLinks = @($siteLinks | Select-Object Name, Cost, ReplicationFrequencyInMinutes, InterSiteTransportProtocol)
                    } `
                    -PotentialImpact 'Inter-site replication may be slower or inconsistent than intended.' `
                    -PossibleCauses @('Manual tuning left over from legacy setup','Wrong frequency value') `
                    -RecommendedInvestigation @('Review each site link and confirm values against design.') `
                    -SuggestedCommands @('Get-ADReplicationSiteLink -Filter * -Properties * | Format-List') `
                    -Duration $sw.Elapsed -ToolUsed 'Get-ADReplicationSiteLink'
                ))
            }
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'REPL-SITE-LINK' -Category 'Replication' `
            -Domain $domain `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'Site link check skipped (cmdlets unavailable)' `
            -WasSkipped $true -SkipReason 'Get-ADReplication* cmdlets not available'
        ))
    }

    # ------------------------------------------------------------------
    # 4) repadmin /replsummary
    # ------------------------------------------------------------------
    if ($Context.Capabilities.Repadmin) {
        $rr = Get-ADHCRepadminReplsummaryRaw -TimeoutSeconds $defaults.Connectivity.Timeouts.Repadmin

        if (-not $rr.Success -or -not $rr.StdOut) {
            $results.Add((New-CheckResult `
                -CheckId 'REPL-REPADMIN-SUMMARY' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title 'repadmin /replsummary did not produce output' `
                -Description 'repadmin.exe failed or returned no stdout.' `
                -Evidence @{ Error = $rr.Error; ExitCode = $rr.ExitCode; StdErr = $rr.StdErr } `
                -IsInconclusive $true -Duration $rr.Duration -ToolUsed 'repadmin'
            ))
            $results.Add((New-CheckResult `
                -CheckId 'REPL-REPADMIN-PARSE' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'Informational' `
                -Title 'repadmin parser skipped (no output)' `
                -WasSkipped $true -SkipReason 'repadmin produced no stdout'
            ))
        } else {
            $parsed = ConvertFrom-ADHCRepadminReplsummary -RawOutput $rr.StdOut

            $parseStatus = 'UNKNOWN'
            if ($parsed.Parsed) { $parseStatus = 'PASS' }

            $results.Add((New-CheckResult `
                -CheckId 'REPL-REPADMIN-PARSE' -Category 'Replication' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status $parseStatus -Severity 'Informational' `
                -Title 'repadmin /replsummary output interpreted' `
                -Description 'Whether the summary headers were recognized by the parser.' `
                -Evidence @{
                    Parsed         = $parsed.Parsed
                    OutboundHeader = $parsed.OutboundHeader
                    InboundHeader  = $parsed.InboundHeader
                    OutboundRows   = $parsed.Outbound.Count
                    InboundRows    = $parsed.Inbound.Count
                    Notes          = $parsed.Notes
                    ExitCode       = $rr.ExitCode
                } `
                -IsInconclusive (-not $parsed.Parsed) `
                -Duration $rr.Duration -ToolUsed 'repadmin'
            ))

            if ($parsed.Parsed) {
                $allRows = @($parsed.Outbound + $parsed.Inbound)
                $totalFails = 0
                foreach ($r in $allRows) { $totalFails += $r.Fails }

                $maxDelta = $null
                foreach ($r in $allRows) {
                    $ts = ConvertFrom-ADHCReplDelta -Delta $r.Delta
                    if ($ts -and ($null -eq $maxDelta -or $ts -gt $maxDelta)) { $maxDelta = $ts }
                }

                if ($allRows.Count -eq 0) {
                    $sumStatus = 'PASS'
                    $sumTitle  = 'repadmin /replsummary reports no partners'
                } elseif ($totalFails -eq 0) {
                    $sumStatus = 'PASS'
                    $sumTitle  = 'repadmin /replsummary reports zero failures'
                } else {
                    $sumStatus = 'FAIL'
                    $sumTitle  = "repadmin /replsummary reports $totalFails failure(s)"
                }

                $sevInfo = Get-ADHCSeverity -CheckId 'REPL-REPADMIN-SUMMARY' -Status $sumStatus

                $rawText = $rr.StdOut
                $rawTruncated = $false
                if ($rawText.Length -gt 4000) {
                    $rawText = $rawText.Substring(0, 4000)
                    $rawTruncated = $true
                }

                $sumImpact = 'No impact.'
                if ($sumStatus -ne 'PASS') {
                    $sumImpact = 'Failures indicated; investigate the failing DSA pair.'
                }

                $maxDeltaText = $null
                if ($maxDelta) { $maxDeltaText = $maxDelta.ToString() }

                $results.Add((New-CheckResult `
                    -CheckId 'REPL-REPADMIN-SUMMARY' -Category 'Replication' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status $sumStatus -Severity $sevInfo.Severity `
                    -Title $sumTitle `
                    -Description 'Structured interpretation of repadmin /replsummary.' `
                    -Evidence @{
                        TotalFailures = $totalFails
                        MaxDelta      = $maxDeltaText
                        OutboundRows  = $parsed.Outbound
                        InboundRows   = $parsed.Inbound
                        Raw           = $rawText
                        RawTruncated  = $rawTruncated
                    } `
                    -PotentialImpact $sumImpact `
                    -PossibleCauses @('DNS','RPC','Firewall','Network','Target DC offline') `
                    -RecommendedInvestigation @('Run repadmin /showrepl on the affected DC','Check Directory Service event log') `
                    -SuggestedCommands @("repadmin /showrepl $env:COMPUTERNAME", "repadmin /replsum /errorsonly") `
                    -Duration $rr.Duration -ToolUsed 'repadmin'
                ))
            } else {
                $rawText = $rr.StdOut
                if ($rawText.Length -gt 4000) { $rawText = $rawText.Substring(0, 4000) }

                $results.Add((New-CheckResult `
                    -CheckId 'REPL-REPADMIN-SUMMARY' -Category 'Replication' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'UNKNOWN' -Severity 'High' `
                    -Title 'repadmin /replsummary output not interpreted' `
                    -Description 'Parser could not recognize the summary headers.' `
                    -Evidence @{ Notes = $parsed.Notes; Raw = $rawText } `
                    -IsInconclusive $true -Duration $rr.Duration -ToolUsed 'repadmin'
                ))
            }
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'REPL-REPADMIN-SUMMARY' -Category 'Replication' `
            -Domain $domain -DomainController $localDc `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'repadmin not available' `
            -WasSkipped $true -SkipReason 'repadmin.exe not found'
        ))
        $results.Add((New-CheckResult `
            -CheckId 'REPL-REPADMIN-PARSE' -Category 'Replication' `
            -Domain $domain -DomainController $localDc `
            -Status 'UNKNOWN' -Severity 'Informational' `
            -Title 'repadmin parser skipped' `
            -WasSkipped $true -SkipReason 'repadmin.exe not found'
        ))
    }

    $results.ToArray()
}

#endregion