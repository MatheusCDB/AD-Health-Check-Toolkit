Set-StrictMode -Version Latest

function Test-ADHCTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 3000
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            return [PSCustomObject]@{ Open=$false; TimedOut=$true;  Duration=$sw.Elapsed; Error='Timeout' }
        }
        $client.EndConnect($iar)
        return [PSCustomObject]@{ Open=$true;  TimedOut=$false; Duration=$sw.Elapsed; Error=$null }
    } catch {
        return [PSCustomObject]@{ Open=$false; TimedOut=$false; Duration=$sw.Elapsed; Error=$_.Exception.Message }
    } finally {
        $client.Close(); $sw.Stop()
    }
}

function Get-ADHCDnsForwardResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Fqdn)
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($Fqdn)
        $ipv4  = @($addrs | Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                   ForEach-Object { $_.IPAddressToString })
        [PSCustomObject]@{ Success=$true; IPv4=$ipv4; Error=$null }
    } catch {
        [PSCustomObject]@{ Success=$false; IPv4=@(); Error=$_.Exception.Message }
    }
}

function Get-ADHCDnsReverseResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IpAddress)
    try {
        $entry = [System.Net.Dns]::GetHostEntry($IpAddress)
        [PSCustomObject]@{ Success=$true; HostName=$entry.HostName; Error=$null }
    } catch {
        [PSCustomObject]@{ Success=$false; HostName=$null; Error=$_.Exception.Message }
    }
}

function Test-ADHCAdminAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [PSCredential]$Credential,
        [int]$TimeoutSeconds = 10
    )
    # 1) WinRM
    $winrmError = $null
    try {
        $params = @{
            ComputerName   = $ComputerName
            ScriptBlock    = { $env:COMPUTERNAME }
            TimeoutSeconds = $TimeoutSeconds
            ErrorAction    = 'Stop'
        }
        if ($Credential) { $params.Credential = $Credential }
        $r = Invoke-ADHCRemote @params
        if ($r.Success) { return [PSCustomObject]@{ Success=$true; Method='WinRM'; Error=$null } }
        $winrmError = $r.Error
    } catch { $winrmError = $_.Exception.Message }

    # 2) CIM (DCOM)
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        if ($cs) { return [PSCustomObject]@{ Success=$true; Method='CIM'; Error=$null } }
    } catch {
        return [PSCustomObject]@{
            Success = $false; Method = $null
            Error   = "WinRM: $winrmError; CIM: $($_.Exception.Message)"
        }
    }
    return [PSCustomObject]@{ Success=$false; Method=$null; Error='No method succeeded.' }
}

function Invoke-ADHCConnectivity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $defaults = Get-ADHCDefaults
    $ports    = $defaults.Connectivity.Ports
    $timeouts = $defaults.Connectivity.Timeouts

    # Ports that are legitimately optional. A closed port here yields INFO/WARNING,
    # not FAIL, and never escalates the domain score.
    $optionalPorts = @(5986)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($dc in $Context.DomainControllers) {
        Write-ADHCLog -Level Info -Message "Connectivity: evaluating $($dc.Fqdn)" -Logger $Context.Logger
        $dcSw = [System.Diagnostics.Stopwatch]::StartNew()

        # --- 1) Forward DNS ---
        $fwdSw = [System.Diagnostics.Stopwatch]::StartNew()
        $fwd = Get-ADHCDnsForwardResult -Fqdn $dc.Fqdn
        $fwdSw.Stop()
        $fwdStatus = if ($fwd.Success -and $fwd.IPv4.Count -gt 0) { 'PASS' } else { 'FAIL' }
        $fwdSev    = Get-ADHCSeverity -CheckId 'CONN-DNS-FWD' -Status $fwdStatus
        $results.Add((New-CheckResult `
            -CheckId 'CONN-DNS-FWD' -Category 'Connectivity' `
            -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
            -Status $fwdStatus -Severity $fwdSev.Severity `
            -Title "Forward DNS resolution of $($dc.Fqdn)" `
            -Description "Resolves $($dc.Fqdn) using the local resolver stack." `
            -Evidence @{ Fqdn=$dc.Fqdn; IPv4=$fwd.IPv4; Error=$fwd.Error } `
            -PotentialImpact 'Unresolved FQDN breaks Kerberos, LDAP, replication and GPO for this DC.' `
            -PossibleCauses @('Missing A record','Stale DNS cache','DNS server unreachable','DC renamed without record update') `
            -RecommendedInvestigation @("Verify A record exists and points to the current DC IP") `
            -SuggestedCommands @("Resolve-DnsName -Name $($dc.Fqdn) -Type A", "Get-DnsServerResourceRecord -ZoneName '$($Context.Domain)' -Name '$($dc.Name)' -RRType A") `
            -Duration $fwdSw.Elapsed -ToolUsed 'System.Net.Dns.GetHostAddresses'
        ))

        # --- 2) Reverse DNS (only if forward succeeded) ---
        $revOk = $false
        if ($fwd.Success -and $fwd.IPv4.Count -gt 0) {
            $revSw = [System.Diagnostics.Stopwatch]::StartNew()
            $rev   = Get-ADHCDnsReverseResult -IpAddress $fwd.IPv4[0]
            $revSw.Stop()
            $revStatus = if ($rev.Success) { 'PASS' } else { 'WARNING' }
            $revSev    = Get-ADHCSeverity -CheckId 'CONN-DNS-REV' -Status $revStatus
            $revOk     = $rev.Success
            $results.Add((New-CheckResult `
                -CheckId 'CONN-DNS-REV' -Category 'Connectivity' `
                -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $fwd.IPv4[0] `
                -Status $revStatus -Severity $revSev.Severity `
                -Title "Reverse DNS (PTR) for $($fwd.IPv4[0])" `
                -Description 'Verifies that the DC IPv4 address resolves back to a name.' `
                -Evidence @{ IpAddress=$fwd.IPv4[0]; PtrHostName=$rev.HostName; Error=$rev.Error } `
                -PotentialImpact 'Missing PTR rarely breaks AD but hampers auditing and some tools.' `
                -PossibleCauses @('Reverse zone not configured','PTR record missing','DNS registration disabled on NIC') `
                -RecommendedInvestigation @('Verify reverse zone exists and PTR record points to the DC FQDN') `
                -SuggestedCommands @("Resolve-DnsName -Name $($fwd.IPv4[0]) -Type PTR") `
                -Duration $revSw.Elapsed -ToolUsed 'System.Net.Dns.GetHostEntry'
            ))
        }

        # --- 3) ICMP ---
        $icmpOk = $false
        if (-not $Context.SkipPing) {
            $icmpSw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $ping = Test-Connection -TargetName $dc.Fqdn -Count 1 -Quiet -ErrorAction SilentlyContinue
                $icmpOk = [bool]$ping
                $icmpErr = $null
            } catch {
                $icmpOk = $false
                $icmpErr = $_.Exception.Message
            }
            $icmpSw.Stop()
            $icmpStatus = if ($icmpOk) { 'PASS' } else { 'WARNING' }
            $icmpSev    = Get-ADHCSeverity -CheckId 'CONN-ICMP' -Status $icmpStatus
            $results.Add((New-CheckResult `
                -CheckId 'CONN-ICMP' -Category 'Connectivity' `
                -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status $icmpStatus -Severity $icmpSev.Severity `
                -Title "ICMP echo to $($dc.Fqdn)" `
                -Description 'Sends a single ICMP echo request.' `
                -Evidence @{ Target=$dc.Fqdn; Success=$icmpOk; Error=$icmpErr } `
                -PotentialImpact 'ICMP is often blocked by firewall; interpret only with other results.' `
                -PossibleCauses @('Firewall blocks ICMP','Network path down','Host offline') `
                -RecommendedInvestigation @('Check firewall rules; prefer TCP port tests as authoritative.') `
                -SuggestedCommands @("Test-Connection -TargetName $($dc.Fqdn) -Count 2") `
                -Duration $icmpSw.Elapsed -ToolUsed 'Test-Connection'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'CONN-ICMP' -Category 'Connectivity' `
                -Domain $Context.Domain -DomainController $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Informational' `
                -Title "ICMP echo to $($dc.Fqdn) (skipped)" `
                -Description 'ICMP test skipped by -SkipPing.' `
                -Evidence @{ Target=$dc.Fqdn; Skipped=$true } `
                -WasSkipped $true -SkipReason 'Skipped by -SkipPing'
            ))
        }

        # --- 4) TCP ports ---
        $anyTcpOk = $false
        foreach ($p in $ports) {
            if (-not $p.TCP) { continue }

            $isOptional = $optionalPorts -contains $p.Port

            $tcpSw  = [System.Diagnostics.Stopwatch]::StartNew()
            $tcpRes = Test-ADHCTcpPort -ComputerName $dc.Fqdn -Port $p.Port -TimeoutMs ($timeouts.Tcp * 1000)
            $tcpSw.Stop()

            if ($tcpRes.Open) { $anyTcpOk = $true }

            if ($tcpRes.Open) {
                $tcpStatus = 'PASS'
                $tcpSev    = [PSCustomObject]@{
                    Severity      = 'Informational'
                    Justification = "Port {0} ({1}) open." -f $p.Port, $p.Name
                    Escalated     = $false
                }
            } elseif ($isOptional) {
                $tcpStatus = 'INFO'
                $tcpSev    = [PSCustomObject]@{
                    Severity      = 'Informational'
                    Justification = "Port {0} ({1}) closed; considered optional in this tool's defaults." -f $p.Port, $p.Name
                    Escalated     = $false
                }
            } else {
                $tcpStatus = 'FAIL'
                $tcpSev    = Get-ADHCSeverity -CheckId 'CONN-TCP' -Status $tcpStatus
            }

            $impactText = if ($isOptional) {
                "$($p.Name) is optional; a closed port here is not, by itself, a domain failure."
            } else {
                "$($p.Name) relies on TCP $($p.Port); a closed port may break dependent functionality."
            }

            $results.Add((New-CheckResult `
                -CheckId ("CONN-TCP-{0}" -f $p.Port) -Category 'Connectivity' `
                -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status $tcpStatus -Severity $tcpSev.Severity `
                -Title ("TCP {0} ({1}) on {2}" -f $p.Port, $p.Name, $dc.Fqdn) `
                -Description ("Opens a TCP socket to {0}:{1}." -f $dc.Fqdn, $p.Port) `
                -Evidence @{ Port=$p.Port; Name=$p.Name; Open=$tcpRes.Open; TimedOut=$tcpRes.TimedOut; Optional=$isOptional; Error=$tcpRes.Error } `
                -PotentialImpact $impactText `
                -PossibleCauses @('Service stopped','Firewall rule','Network path','Wrong IP','Optional listener not configured') `
                -RecommendedInvestigation @("Test-NetConnection $($dc.Fqdn) -Port $($p.Port)", "Check firewall rules and service status on the DC") `
                -SuggestedCommands @("Test-NetConnection -ComputerName $($dc.Fqdn) -Port $($p.Port)") `
                -Duration $tcpSw.Elapsed -ToolUsed 'System.Net.Sockets.TcpClient'
            ))
        }

        # --- 5) Admin access ---
        $adminSw = [System.Diagnostics.Stopwatch]::StartNew()
        $admin   = Test-ADHCAdminAccess -ComputerName $dc.Fqdn -Credential $Context.Credential -TimeoutSeconds 10
        $adminSw.Stop()
        $adminStatus = if ($admin.Success) { 'PASS' } else { 'WARNING' }
        $adminSev    = Get-ADHCSeverity -CheckId 'CONN-ADMIN' -Status $adminStatus
        $results.Add((New-CheckResult `
            -CheckId 'CONN-ADMIN' -Category 'Connectivity' `
            -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
            -Status $adminStatus -Severity $adminSev.Severity `
            -Title "Administrative access to $($dc.Fqdn)" `
            -Description 'Tries WinRM, then CIM over DCOM, to check remote administrative access.' `
            -Evidence @{ Method=$admin.Method; Success=$admin.Success; Error=$admin.Error } `
            -PotentialImpact 'Without admin access, deeper remote checks on this DC will be marked UNKNOWN.' `
            -PossibleCauses @('WinRM disabled','Firewall blocks RPC','Insufficient privileges','Kerberos issue') `
            -RecommendedInvestigation @('Verify the executing account has rights on the DC','Check WinRM listener and firewall') `
            -SuggestedCommands @("Test-WSMan -ComputerName $($dc.Fqdn)") `
            -Duration $adminSw.Elapsed -ToolUsed 'WinRM / CIM'
        ))

        # --- 6) Reachability summary ---
        $isReachable = $fwd.Success -and $fwd.IPv4.Count -gt 0 -or $anyTcpOk -or $admin.Success
        $reachStatus = if ($isReachable) { 'PASS' } else { 'FAIL' }
        $reachSev    = Get-ADHCSeverity -CheckId 'CONN-REACH' -Status $reachStatus
        $results.Add((New-CheckResult `
            -CheckId 'CONN-REACH' -Category 'Connectivity' `
            -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
            -Status $reachStatus -Severity $reachSev.Severity `
            -Title "Reachability summary for $($dc.Fqdn)" `
            -Description 'Aggregates DNS, TCP and admin signals to classify the DC as reachable.' `
            -Evidence @{
                DnsForwardSuccess = $fwd.Success
                AnyTcpOpen        = $anyTcpOk
                AdminAccess       = $admin.Success
                IsReachable       = $isReachable
            } `
            -PotentialImpact 'Unreachable DCs cannot be diagnosed remotely; results for them will be sparse.' `
            -PossibleCauses @('DC offline','Network partition','DNS misconfiguration','Firewall') `
            -RecommendedInvestigation @('Investigate network path and DC boot state before other checks.') `
            -SuggestedCommands @("Test-NetConnection -ComputerName $($dc.Fqdn) -Port 389") `
            -Duration $dcSw.Elapsed -ToolUsed 'Aggregate'
        ))

        $dcSw.Stop()
        Write-ADHCLog -Level Info -Message "Connectivity: done for $($dc.Fqdn) in $($dcSw.Elapsed.TotalSeconds.ToString('F1'))s" -Logger $Context.Logger
    }

    $results.ToArray()
}