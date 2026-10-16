Set-StrictMode -Version Latest

#region --- Parser: dcdiag /test:dns output (pt-BR / en-US) ---

function ConvertFrom-ADHCDcdiagDnsSummary {
    <#
    .SYNOPSIS
        Parses the final summary table produced by `dcdiag /test:dns /v`.

        The table looks like this in pt-BR:

                                                Auth Basc Forw Del  Dyn  RReg Ext
            _________________________________________________________________
            Domínio: crg.local
               AD02                         PASS PASS PASS PASS PASS PASS n/a

        and like this in en-US:

                                                Auth Basc Forw Del  Dyn  RReg Ext
            _________________________________________________________________
            Domain: contoso.local
               DC01                         PASS PASS PASS PASS PASS PASS n/a

        We deliberately parse only the final summary table (structural, not prose).
        If it is not found, we return Parsed=$false and the caller emits UNKNOWN.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed         = $false
        Domain         = $null
        DcRows         = @()
        OverallVerdict = $null
        Notes          = @()
    }

    if (-not $RawOutput) { return $result }

    $lines = $RawOutput -split "`r?`n"

    # Find the header row: must contain Auth, Basc, Forw, Del, Dyn, RReg (in that order).
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match 'Auth\s+Basc\s+Forw\s+Del\s+Dyn\s+RReg') { $headerIdx = $i; break }
    }
    if ($headerIdx -lt 0) {
        $result.Notes += 'Header row (Auth Basc Forw Del Dyn RReg) not found.'
        return $result
    }

    # Walk forward collecting DC rows until a non-matching line.
    $domainName = $null
    $rows = [System.Collections.Generic.List[object]]::new()

    for ($i = $headerIdx + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd()
        if (-not $line) { continue }
        if ($line -match '^_+\s*$') { continue }

        # Domain/Domínio: line
        if ($line -match '^\s*(?:Dom[ií]nio|Domain)\s*:\s*(\S+)\s*$') {
            $domainName = $Matches[1]
            continue
        }

        # DC row: leading whitespace, DC name, then 6-7 uppercase tokens.
        # Example: "   AD02                         PASS PASS PASS PASS PASS PASS n/a"
        $m = [regex]::Match($line, '^\s*(\S+)\s+((?:PASS|FAIL|WARN|n/a|N/A)(?:\s+(?:PASS|FAIL|WARN|n/a|N/A)){5,6})\s*$')
        if ($m.Success) {
            $dcName = $m.Groups[1].Value
            $tokens = $m.Groups[2].Value -split '\s+' | Where-Object { $_ }
            if ($tokens.Count -lt 6) { continue }

            $row = [PSCustomObject]@{
                Dc   = $dcName
                Auth = $tokens[0]
                Basc = $tokens[1]
                Forw = $tokens[2]
                Del  = $tokens[3]
                Dyn  = $tokens[4]
                RReg = $tokens[5]
                Ext  = if ($tokens.Count -ge 7) { $tokens[6] } else { $null }
            }
            $rows.Add($row)
            continue
        }

        # Stop at the first line that looks like prose after the table started.
        if ($rows.Count -gt 0) {
            # We tolerate blank/underscore lines handled above; anything else ends the block.
            break
        }
    }

    if ($rows.Count -gt 0) {
        $result.Parsed = $true
        $result.Domain = $domainName
        $result.DcRows = $rows.ToArray()

        # Overall verdict: last line matching "... passou no teste DNS" / "... passed test DNS"
        $verdict = $null
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $l = $lines[$i]
            if ($l -match '(\S+)\s+passou no teste DNS') { $verdict = 'PASS'; break }
            if ($l -match '(\S+)\s+passed test DNS')    { $verdict = 'PASS'; break }
            if ($l -match '(\S+)\s+falhou no teste DNS') { $verdict = 'FAIL'; break }
            if ($l -match '(\S+)\s+failed test DNS')    { $verdict = 'FAIL'; break }
        }
        $result.OverallVerdict = $verdict
    } else {
        $result.Notes += 'Header found but no DC rows could be parsed.'
    }

    $result
}

#endregion

#region --- Helpers ---

function Resolve-ADHCSrvRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Server
    )
    try {
        $params = @{ Name = $Name; Type = 'SRV'; ErrorAction = 'Stop' }
        if ($Server) { $params.Server = $Server }
        $records = Resolve-DnsName @params
        $srv = @($records | Where-Object { $_.Type -eq 'SRV' })
        [PSCustomObject]@{
            Success = ($srv.Count -gt 0)
            Records = $srv
            Error   = $null
        }
    } catch {
        [PSCustomObject]@{
            Success = $false
            Records = @()
            Error   = $_.Exception.Message
        }
    }
}

function Get-ADHCAHostRecordsForDc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Fqdn,
        [string]$Server
    )
    try {
        $params = @{ Name = $Fqdn; Type = 'A'; ErrorAction = 'Stop' }
        if ($Server) { $params.Server = $Server }
        $records = Resolve-DnsName @params
        $a = @($records | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress })
        [PSCustomObject]@{ Success = $true; IPv4 = $a; Error = $null }
    } catch {
        [PSCustomObject]@{ Success = $false; IPv4 = @(); Error = $_.Exception.Message }
    }
}

function Test-ADHCIpReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IpAddress,
        [int]$TimeoutMs = 2000
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        # Test 389 (LDAP) as a lightweight AD-specific liveness probe on the target IP.
        $iar = $client.BeginConnect($IpAddress, 389, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCDns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $results = [System.Collections.Generic.List[object]]::new()
    $domain  = $Context.Domain
    $caps    = $Context.Capabilities

    foreach ($dc in $Context.DomainControllers) {
        Write-ADHCLog -Level Info -Message "DNS: evaluating $($dc.Fqdn)" -Logger $Context.Logger
        $dcSw = [System.Diagnostics.Stopwatch]::StartNew()

        $isLocal = Test-ADHCIsLocalhost -ComputerName $dc.Fqdn

        # ------------------------------------------------------------------
        # 1) Zone existence / AD-integration / SOA / NS (requires DnsServer module)
        # ------------------------------------------------------------------
        $zoneInfo = $null
        $zoneQueryFailed = $false
        $zoneQueryError  = $null

        if (-not $caps.DnsServer) {
            $zoneQueryFailed = $true
            $zoneQueryError  = 'DnsServer PowerShell module not available on the evaluation host.'
        } elseif (-not $isLocal) {
            $zoneQueryFailed = $true
            $zoneQueryError  = 'DNS zone checks are only performed on the local DC (per design option (a)).'
        } else {
            try {
                $z = Get-DnsServerZone -ZoneName $domain -ErrorAction Stop
                $zoneInfo = $z
            } catch {
                $zoneQueryFailed = $true
                $zoneQueryError  = $_.Exception.Message
            }
        }

        if ($zoneQueryFailed) {
            $results.Add((New-CheckResult `
                -CheckId 'DNS-ZONE-QUERY' -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "Could not query DNS zones for $domain" `
                -Description 'Zone enumeration via Get-DnsServerZone did not run.' `
                -Evidence @{ Reason = $zoneQueryError; DnsServerModule = $caps.DnsServer; IsLocal = $isLocal } `
                -PotentialImpact 'Zone-level checks (existence, AD-integration, SOA) are not evaluated.' `
                -PossibleCauses @('DnsServer module missing','DC does not host DNS','Evaluation host is not the DC') `
                -RecommendedInvestigation @("Install RSAT-DNS-Server if applicable","Run the tool directly on a DNS-hosting DC") `
                -SuggestedCommands @('Get-DnsServerZone','Import-Module DnsServer') `
                -IsInconclusive $true -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerZone'
            ))

            $results.Add((New-CheckResult `
                -CheckId 'DNS-ZONE-EXISTS' -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title "Zone $domain existence not evaluated" `
                -Description 'Precondition failed: zone enumeration did not run.' `
                -Evidence @{ Reason = $zoneQueryError } `
                -WasSkipped $true -SkipReason 'Zone enumeration unavailable'
            ))
            $results.Add((New-CheckResult `
                -CheckId 'DNS-ZONE-AD' -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title "Zone $domain AD-integration not evaluated" `
                -Description 'Precondition failed: zone enumeration did not run.' `
                -Evidence @{ Reason = $zoneQueryError } `
                -WasSkipped $true -SkipReason 'Zone enumeration unavailable'
            ))
        } else {
            # DNS-ZONE-EXISTS
            if ($zoneInfo) {
                $results.Add((New-CheckResult `
                    -CheckId 'DNS-ZONE-EXISTS' -Category 'DNS' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'PASS' -Severity 'High' `
                    -Title "Zone $domain exists on $($dc.Fqdn)" `
                    -Description 'The AD DNS zone is present on this DC.' `
                    -Evidence @{ ZoneName = $zoneInfo.ZoneName; ZoneType = $zoneInfo.ZoneType.ToString() } `
                    -PotentialImpact 'No impact.' `
                    -PossibleCauses @() `
                    -RecommendedInvestigation @() `
                    -SuggestedCommands @("Get-DnsServerZone -ZoneName $domain") `
                    -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerZone'
                ))

                # DNS-ZONE-AD
                if ($zoneInfo.IsDsIntegrated) {
                    $results.Add((New-CheckResult `
                        -CheckId 'DNS-ZONE-AD' -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'PASS' -Severity 'High' `
                        -Title "Zone $domain is AD-integrated" `
                        -Description 'Zone is replicated via Active Directory.' `
                        -Evidence @{ IsDsIntegrated = $true; ZoneType = $zoneInfo.ZoneType.ToString() } `
                        -PotentialImpact 'No impact.' `
                        -SuggestedCommands @("Get-DnsServerZone -ZoneName $domain | Format-List *") `
                        -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerZone'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'DNS-ZONE-AD' -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'FAIL' -Severity 'High' `
                        -Title "Zone $domain is NOT AD-integrated" `
                        -Description 'ZoneType is not AD-integrated. Records will not replicate via AD.' `
                        -Evidence @{ IsDsIntegrated = $false; ZoneType = $zoneInfo.ZoneType.ToString() } `
                        -PotentialImpact 'Multi-DC environments will diverge; updates will not propagate automatically.' `
                        -PossibleCauses @('Zone was created as a standard primary','Migrated from BIND without AD integration') `
                        -RecommendedInvestigation @('Confirm intent; converting to AD-integrated is a deliberate change.') `
                        -SuggestedCommands @("Get-DnsServerZone -ZoneName $domain | Format-List IsDsIntegrated, ZoneType") `
                        -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerZone'
                    ))
                }

                # SOA sanity
                try {
                    $soa = Get-DnsServerResourceRecord -ZoneName $domain -RRType Soa -ErrorAction Stop
                    $soaPrimary = $soa.RecordData.PrimaryServer
                    $dcNames = @($Context.DomainControllers | ForEach-Object { $_.Name })
                    $soaHost = ($soaPrimary -split '\.')[0]
                    if ($dcNames -contains $soaHost) {
                        $results.Add((New-CheckResult `
                            -CheckId 'DNS-ZONE-SOA' -Category 'DNS' `
                            -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                            -Status 'PASS' -Severity 'Medium' `
                            -Title "SOA primary of $domain points to a known DC" `
                            -Description 'SOA primary server resolves to a DC discovered in this domain.' `
                            -Evidence @{ PrimaryServer = $soaPrimary; SoaHost = $soaHost } `
                            -PotentialImpact 'No impact.' `
                            -SuggestedCommands @("Get-DnsServerResourceRecord -ZoneName $domain -RRType Soa | Format-List") `
                            -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerResourceRecord'
                        ))
                    } else {
                        $results.Add((New-CheckResult `
                            -CheckId 'DNS-ZONE-SOA' -Category 'DNS' `
                            -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                            -Status 'WARNING' -Severity 'Medium' `
                            -Title "SOA primary of $domain does not match a known DC" `
                            -Description 'SOA primary server hostname is not among the discovered DCs.' `
                            -Evidence @{ PrimaryServer = $soaPrimary; KnownDcs = $dcNames } `
                            -PotentialImpact 'Updates may land on unexpected host; investigate intent.' `
                            -PossibleCauses @('DC renamed','Legacy primary retained','Manual zone setup') `
                            -RecommendedInvestigation @('Verify SOA against the intended primary DNS server.') `
                            -SuggestedCommands @("Get-DnsServerResourceRecord -ZoneName $domain -RRType Soa | Format-List") `
                            -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerResourceRecord'
                        ))
                    }
                } catch {
                    $results.Add((New-CheckResult `
                        -CheckId 'DNS-ZONE-SOA' -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'UNKNOWN' -Severity 'Medium' `
                        -Title "SOA of $domain could not be read" `
                        -Description 'Get-DnsServerResourceRecord -RRType Soa failed.' `
                        -Evidence @{ Error = $_.Exception.Message } `
                        -IsInconclusive $true -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerResourceRecord'
                    ))
                }
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'DNS-ZONE-EXISTS' -Category 'DNS' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'FAIL' -Severity 'High' `
                    -Title "Zone $domain NOT found on $($dc.Fqdn)" `
                    -Description 'The AD DNS zone is missing on this DC.' `
                    -Evidence @{ ZoneName = $domain; Found = $false } `
                    -PotentialImpact 'This DC cannot answer queries for the domain zone.' `
                    -PossibleCauses @('DNS role not installed','Zone deleted','Not a DNS-hosting DC') `
                    -RecommendedInvestigation @('Verify DNS role and zone presence on this DC.') `
                    -SuggestedCommands @("Get-DnsServerZone | Where-Object ZoneName -eq '$domain'") `
                    -Duration $dcSw.Elapsed -ToolUsed 'Get-DnsServerZone'
                ))
            }
        }

        # ------------------------------------------------------------------
        # 2) SRV records via Resolve-DnsName (works remotely and locally)
        # ------------------------------------------------------------------
        $srvChecks = @(
            @{ Id='DNS-SRV-LDAP'; Name="_ldap._tcp.dc._msdcs.$domain";         Sev='High'     }
            @{ Id='DNS-SRV-KERB'; Name="_kerberos._tcp.$domain";              Sev='Critical' }
            @{ Id='DNS-SRV-PDC';  Name="_ldap._tcp.pdc._msdcs.$domain";       Sev='High'     }
            @{ Id='DNS-SRV-GC';   Name="_gc._tcp.$domain";                    Sev='Medium'   }
        )

        foreach ($s in $srvChecks) {
            $srvSw = [System.Diagnostics.Stopwatch]::StartNew()
            $res = Resolve-ADHCSrvRecord -Name $s.Name
            $srvSw.Stop()

            if ($res.Success) {
                $status = 'PASS'
                $targets = @($res.Records | ForEach-Object { "$($_.NameTarget):$($_.Port)" })
                $evidence = @{ Query = $s.Name; Records = $targets; Error = $null }
                $sevOverride = $null
            } else {
                # Resolve-DnsName threw vs returned empty. Empty is FAIL; throw is UNKNOWN.
                if ($res.Error) {
                    $status = 'UNKNOWN'
                    $evidence = @{ Query = $s.Name; Error = $res.Error }
                    $sevOverride = 'Medium'
                } else {
                    $status = 'FAIL'
                    $evidence = @{ Query = $s.Name; Records = @(); Error = $null }
                    $sevOverride = $null
                }
            }

            if ($sevOverride) {
                $sev = [PSCustomObject]@{ Severity = $sevOverride; Justification = 'Resolution attempt could not complete.'; Escalated = $false }
            } else {
                $sev = Get-ADHCSeverity -CheckId $s.Id -Status $status
            }

            $title = switch ($s.Id) {
                'DNS-SRV-LDAP' { "LDAP SRV record for $domain" }
                'DNS-SRV-KERB' { "Kerberos SRV record for $domain" }
                'DNS-SRV-PDC'  { "PDC SRV record for $domain" }
                'DNS-SRV-GC'   { "Global Catalog SRV record for $domain" }
            }

            $results.Add((New-CheckResult `
                -CheckId $s.Id -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status $status -Severity $sev.Severity `
                -Title $title `
                -Description "Resolves SRV $($s.Name) against the default resolver." `
                -Evidence $evidence `
                -PotentialImpact ("Service locator for {0} depends on this SRV record." -f $s.Id) `
                -PossibleCauses @('Missing registration','Zone not AD-integrated','Netlogon not running','Dynamic update disabled') `
                -RecommendedInvestigation @("Verify Netlogon is running on at least one DC","Verify DNS dynamic updates are enabled") `
                -SuggestedCommands @("Resolve-DnsName -Name '$($s.Name)' -Type SRV","nltest /dsgetdc:$domain") `
                -IsInconclusive ($status -eq 'UNKNOWN') `
                -Duration $srvSw.Elapsed -ToolUsed 'Resolve-DnsName'
            ))
        }

        # ------------------------------------------------------------------
        # 3) Multiple A records per DC (INFO)
        # ------------------------------------------------------------------
        $aSw = [System.Diagnostics.Stopwatch]::StartNew()
        $aRes = Get-ADHCAHostRecordsForDc -Fqdn $dc.Fqdn
        $aSw.Stop()

        if ($aRes.Success) {
            $count = $aRes.IPv4.Count
            if ($count -gt 1) {
                $results.Add((New-CheckResult `
                    -CheckId 'DNS-MULTI-A' -Category 'DNS' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'INFO' -Severity 'Informational' `
                    -Title "Multiple A records for $($dc.Fqdn)" `
                    -Description "The DC FQDN resolves to $count IPv4 addresses." `
                    -Evidence @{ Fqdn = $dc.Fqdn; IPv4 = $aRes.IPv4 } `
                    -PotentialImpact 'Normal for multi-NIC DCs; verify all IPs are reachable by clients.' `
                    -PossibleCauses @('Multiple NICs','Stale registration left behind') `
                    -RecommendedInvestigation @('Confirm both IPs are intended and reachable from client subnets.') `
                    -SuggestedCommands @("Resolve-DnsName -Name '$($dc.Fqdn)' -Type A") `
                    -Duration $aSw.Elapsed -ToolUsed 'Resolve-DnsName'
                ))
            }

            # ------------------------------------------------------------------
            # 4) Reverse DNS for each IPv4 (INFO)
            # ------------------------------------------------------------------
            foreach ($ip in $aRes.IPv4) {
                $revSw = [System.Diagnostics.Stopwatch]::StartNew()
                $revOk = $false
                $revHost = $null
                $revErr  = $null
                try {
                    $rev = Resolve-DnsName -Name $ip -Type PTR -ErrorAction Stop
                    $ptr = @($rev | Where-Object { $_.Type -eq 'PTR' })
                    if ($ptr.Count -gt 0) { $revOk = $true; $revHost = $ptr[0].NameHost }
                } catch {
                    $revErr = $_.Exception.Message
                }
                $revSw.Stop()

                if (-not $revOk) {
                    $results.Add((New-CheckResult `
                        -CheckId ("DNS-REVERSE-MISSING-{0}" -f ($ip -replace '\.','-')) -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $ip `
                        -Status 'INFO' -Severity 'Informational' `
                        -Title "No PTR for $ip" `
                        -Description 'Reverse lookup did not return a PTR record for this DC IPv4.' `
                        -Evidence @{ IpAddress = $ip; Ptr = $revHost; Error = $revErr } `
                        -PotentialImpact 'Missing PTR rarely breaks AD; affects auditing and some tools.' `
                        -PossibleCauses @('Reverse zone not configured','PTR record not registered') `
                        -RecommendedInvestigation @('Configure reverse zone / PTR if required by your policy.') `
                        -SuggestedCommands @("Resolve-DnsName -Name '$ip' -Type PTR","Get-DnsServerZone | Where-Object IsReverseLookupZone") `
                        -Duration $revSw.Elapsed -ToolUsed 'Resolve-DnsName'
                    ))
                }
            }
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'DNS-FWD' -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "A records for $($dc.Fqdn) not evaluated" `
                -Description 'Resolve-DnsName failed while querying A records.' `
                -Evidence @{ Error = $aRes.Error } `
                -IsInconclusive $true -Duration $aSw.Elapsed -ToolUsed 'Resolve-DnsName'
            ))
        }

        # ------------------------------------------------------------------
        # 5) dcdiag /test:dns (secondary evidence, best-effort)
        # ------------------------------------------------------------------
        if ($caps.Dcdiag -and $isLocal) {
            $dcdSw = [System.Diagnostics.Stopwatch]::StartNew()
            $rawOut = $null
            $rawErr = $null
            $exit   = $null

            try {
                # Redirect both streams; dcdiag writes progress to stdout.
                $tmp = [System.IO.Path]::GetTempFileName()
                $p = Start-Process -FilePath 'dcdiag.exe' `
                    -ArgumentList @('/test:dns', '/v') `
                    -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $tmp `
                    -RedirectStandardError  ($tmp + '.err') `
                    -ErrorAction Stop

                $exit = $p.ExitCode

                # dcdiag writes to the OEM code page (CP-850 on Windows pt-BR).
                $oemEnc = [System.Text.Encoding]::GetEncoding([int][System.Text.Encoding]::Default.CodePage)
                if ([System.Text.Encoding]::Default.CodePage -eq 1252) {
                    $oemEnc = [System.Text.Encoding]::GetEncoding(850)
                }

                $rawOut = $null
                $rawErr = $null
                if (Test-Path -LiteralPath $tmp) {
                    $bytesOut = [System.IO.File]::ReadAllBytes($tmp)
                    $rawOut = $oemEnc.GetString($bytesOut)
                }
                if (Test-Path -LiteralPath ($tmp + '.err')) {
                    $bytesErr = [System.IO.File]::ReadAllBytes($tmp + '.err')
                    $rawErr = $oemEnc.GetString($bytesErr)
                }

                Remove-Item -LiteralPath $tmp, ($tmp + '.err') -Force -ErrorAction SilentlyContinue
            } catch {
                $rawErr = $_.Exception.Message
            }
            $dcdSw.Stop()

            if ($rawOut) {
                $parsed = ConvertFrom-ADHCDcdiagDnsSummary -RawOutput $rawOut

                # DNS-DCDIAG-PARSE
                $parseStatus = if ($parsed.Parsed) { 'PASS' } else { 'UNKNOWN' }
                $results.Add((New-CheckResult `
                    -CheckId 'DNS-DCDIAG-PARSE' -Category 'DNS' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status $parseStatus -Severity 'Informational' `
                    -Title 'dcdiag /test:dns output interpreted' `
                    -Description 'Whether the summary table was recognized by the parser.' `
                    -Evidence @{
                        Parsed   = $parsed.Parsed
                        Domain   = $parsed.Domain
                        Notes    = $parsed.Notes
                        ExitCode = $exit
                    } `
                    -PotentialImpact 'If not parsed, DNS-DCDIAG is reported as UNKNOWN.' `
                    -IsInconclusive (-not $parsed.Parsed) `
                    -Duration $dcdSw.Elapsed -ToolUsed 'dcdiag'
                ))

                if ($parsed.Parsed) {
                    $anyFail = $false
                    $anyWarn = $false
                    foreach ($row in $parsed.DcRows) {
                        foreach ($t in @($row.Auth,$row.Basc,$row.Forw,$row.Del,$row.Dyn,$row.RReg,$row.Ext)) {
                            if ($t -eq 'FAIL') { $anyFail = $true }
                            if ($t -eq 'WARN') { $anyWarn = $true }
                        }
                    }
                    $status = if ($anyFail) { 'FAIL' } elseif ($anyWarn) { 'WARNING' } else { 'PASS' }
                    $sev    = Get-ADHCSeverity -CheckId 'DNS-DCDIAG' -Status $status

                    $results.Add((New-CheckResult `
                        -CheckId 'DNS-DCDIAG' -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status $status -Severity $sev.Severity `
                        -Title "dcdiag /test:dns summary" `
                        -Description 'Aggregated verdict from dcdiag /test:dns summary table.' `
                        -Evidence @{
                            OverallVerdict = $parsed.OverallVerdict
                            Rows           = $parsed.DcRows
                            Raw            = if ($rawOut.Length -gt 4000) { $rawOut.Substring(0, 4000) } else { $rawOut }
                            RawTruncated   = ($rawOut.Length -gt 4000)
                        } `
                        -PotentialImpact 'A non-PASS summary indicates DNS dependency issues for this DC.' `
                        -PossibleCauses @('Refer to Rows evidence for the failing column (Auth/Basc/Forw/Del/Dyn/RReg/Ext).') `
                        -RecommendedInvestigation @('Review the failing column in the summary table.','Refer to raw dcdiag output for details.') `
                        -SuggestedCommands @('dcdiag /test:dns /v') `
                        -Duration $dcdSw.Elapsed -ToolUsed 'dcdiag'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'DNS-DCDIAG' -Category 'DNS' `
                        -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                        -Status 'UNKNOWN' -Severity 'High' `
                        -Title 'dcdiag /test:dns output not interpreted' `
                        -Description 'Summary table was not recognized; raw output preserved for review.' `
                        -Evidence @{
                            Notes = $parsed.Notes
                            Raw   = if ($rawOut.Length -gt 4000) { $rawOut.Substring(0, 4000) } else { $rawOut }
                            RawTruncated = ($rawOut.Length -gt 4000)
                        } `
                        -IsInconclusive $true -Duration $dcdSw.Elapsed -ToolUsed 'dcdiag'
                    ))
                }
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'DNS-DCDIAG' -Category 'DNS' `
                    -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status 'UNKNOWN' -Severity 'High' `
                    -Title 'dcdiag /test:dns did not produce output' `
                    -Description 'dcdiag returned no stdout; see Error for details.' `
                    -Evidence @{ Error = $rawErr; ExitCode = $exit } `
                    -IsInconclusive $true -Duration $dcdSw.Elapsed -ToolUsed 'dcdiag'
                ))
            }
        } else {
            $reason = if (-not $caps.Dcdiag) { 'dcdiag.exe not available.' } else { 'Only executed on the local DC (design option (a)).' }
            $results.Add((New-CheckResult `
                -CheckId 'DNS-DCDIAG' -Category 'DNS' `
                -Domain $domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title 'dcdiag /test:dns skipped' `
                -Description $reason `
                -Evidence @{ Reason = $reason; Dcdiag = $caps.Dcdiag; IsLocal = $isLocal } `
                -WasSkipped $true -SkipReason $reason
            ))
        }

        $dcSw.Stop()
        Write-ADHCLog -Level Info -Message "DNS: done for $($dc.Fqdn) in $($dcSw.Elapsed.TotalSeconds.ToString('F1'))s" -Logger $Context.Logger
    }

    $results.ToArray()
}

#endregion