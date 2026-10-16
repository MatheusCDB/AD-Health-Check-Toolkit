Set-StrictMode -Version Latest

#region --- w32tm parsers (pt-BR / en-US) ---

function ConvertFrom-ADHCW32tmStatus {
    <#
    .SYNOPSIS
        Parses `w32tm /query /status` (pt-BR and en-US).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed           = $false
        LeapIndicator    = $null
        Stratum          = $null
        Precision        = $null
        RootDelay        = $null
        RootDispersion   = $null
        ReferenceId      = $null
        ReferenceIp      = $null
        LastSuccessSync  = $null
        Source           = $null
        PollIntervalSec  = $null
        Notes            = @()
    }

    if (-not $RawOutput) { return $result }

    # Match a "Label: value" line, using a label regex.
    function _GetValue([string]$text, [string]$labelPattern) {
        $m = [regex]::Match($text, "(?m)^\s*(?:$labelPattern)\s*:\s*(.+?)\s*$")
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }

    $leap = _GetValue $RawOutput 'Indicador de Salto|Leap Indicator'
    if ($leap) {
        # e.g. "0(sem aviso)" or "0(no warning)"
        $m = [regex]::Match($leap, '^(\d+)')
        if ($m.Success) { $result.LeapIndicator = [int]$m.Groups[1].Value }
    }

    $stratum = _GetValue $RawOutput 'Camada|Stratum'
    if ($stratum) {
        $m = [regex]::Match($stratum, '^(\d+)')
        if ($m.Success) { $result.Stratum = [int]$m.Groups[1].Value }
    }

    $result.Precision      = _GetValue $RawOutput 'Precis.o|Precision'
    $result.RootDelay      = _GetValue $RawOutput 'Atraso de Raiz|Root Delay'
    $result.RootDispersion = _GetValue $RawOutput 'Dispers.o de Raiz|Root Dispersion'

    $refId = _GetValue $RawOutput 'ID de refer.ncia|Reference ID'
    if ($refId) {
        $result.ReferenceId = $refId
        $ip = [regex]::Match($refId, '\(.*?(\d+\.\d+\.\d+\.\d+)\)')
        if ($ip.Success) { $result.ReferenceIp = $ip.Groups[1].Value }
    }

    $lastSync = _GetValue $RawOutput '.ltima Sincroniza..o com .xito|Last Successful Sync Time'
    $result.LastSuccessSync = $lastSync

    $src = _GetValue $RawOutput 'Fonte|Source'
    $result.Source = $src

    $poll = _GetValue $RawOutput 'Intervalo de Sondagem|Poll Interval'
    if ($poll) {
        $m = [regex]::Match($poll, '\((\d+)s\)')
        if ($m.Success) { $result.PollIntervalSec = [int]$m.Groups[1].Value }
    }

    if ($result.Stratum -ne $null -and $result.Source) {
        $result.Parsed = $true
    } else {
        $result.Notes += 'Could not extract Stratum and/or Source.'
    }
    $result
}

function ConvertFrom-ADHCW32tmConfiguration {
    <#
    .SYNOPSIS
        Parses `w32tm /query /configuration` for NtpClient Type and NtpServer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed    = $false
        Type      = $null
        NtpServer = $null
        Notes     = @()
    }

    if (-not $RawOutput) { return $result }

    # We look for the NtpClient provider block first.
    $ntpClientBlock = [regex]::Match($RawOutput, '(?s)NtpClient[^\r\n]*\r?\n(.*?)(?=\r?\n[A-Za-z]+\s*\(Local\)|\z)')
    $searchScope = $RawOutput
    if ($ntpClientBlock.Success) { $searchScope = $ntpClientBlock.Groups[1].Value }

    $typeM = [regex]::Match($searchScope, '(?m)^\s*Type\s*:\s*(\S+)')
    if ($typeM.Success) { $result.Type = $typeM.Groups[1].Value }

    $serverM = [regex]::Match($searchScope, '(?m)^\s*NtpServer\s*:\s*(.+?)\s*$')
    if ($serverM.Success) { $result.NtpServer = $serverM.Groups[1].Value }

    if ($result.Type) { $result.Parsed = $true }
    else { $result.Notes += 'Type not found in configuration output.' }

    $result
}

function ConvertFrom-ADHCW32tmPeers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed = $false
        Peers  = @()
        Notes  = @()
    }

    if (-not $RawOutput) { return $result }

    # Peers are reported as blocks starting with a "Ponto: <host>" or "Peer: <host>".
    $blocks = [regex]::Matches($RawOutput, '(?m)^\s*(?:Ponto|Peer)\s*:\s*(\S+)\s*$')
    if ($blocks.Count -eq 0) {
        $result.Notes += 'No peer blocks found.'
        return $result
    }

    foreach ($b in $blocks) {
        $hostName = $b.Groups[1].Value
        $after = $RawOutput.Substring($b.Index)
        # Cut at next peer block.
        $nextBlock = [regex]::Match($after.Substring($b.Length), '(?m)^\s*(?:Ponto|Peer)\s*:')
        if ($nextBlock.Success) { $after = $after.Substring(0, $b.Length + $nextBlock.Index) }

        $state  = $null
        $mode   = $null
        $stratum = $null
        $mState  = [regex]::Match($after, '(?m)^\s*(?:Estado|State)\s*:\s*(.+?)\s*$')
        if ($mState.Success) { $state = $mState.Groups[1].Value }
        $mMode   = [regex]::Match($after, '(?m)^\s*(?:Modo|Mode)\s*:\s*(.+?)\s*$')
        if ($mMode.Success)  { $mode = $mMode.Groups[1].Value }
        $mStr    = [regex]::Match($after, '(?m)^\s*(?:Camada|Stratum)\s*:\s*(\d+)')
        if ($mStr.Success)   { $stratum = [int]$mStr.Groups[1].Value }

        $result.Peers += [PSCustomObject]@{
            Peer     = $hostName
            State    = $state
            Mode     = $mode
            Stratum  = $stratum
        }
    }

    $result.Parsed = ($result.Peers.Count -gt 0)
    $result
}

function ConvertFrom-ADHCW32tmStripchart {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RawOutput)

    $result = [PSCustomObject]@{
        Parsed    = $false
        Samples   = @()
        MaxOffsetSec = $null
        Notes     = @()
    }

    if (-not $RawOutput) { return $result }

    # Samples look like: "08:57:22, +00.0020093s"  (or "-00.0020093s")
    $sampleMatches = [regex]::Matches($RawOutput, '(?m)^\s*(\d{2}:\d{2}:\d{2}),\s*([+-]?\d+(?:\.\d+)?)s\s*$')
    if ($sampleMatches.Count -eq 0) {
        $result.Notes += 'No stripchart samples found.'
        return $result
    }

    $maxAbs = 0.0
    foreach ($m in $sampleMatches) {
        $offset = [double]$m.Groups[2].Value
        $result.Samples += [PSCustomObject]@{
            Time   = $m.Groups[1].Value
            OffsetSec = $offset
        }
        $abs = [math]::Abs($offset)
        if ($abs -gt $maxAbs) { $maxAbs = $abs }
    }
    $result.MaxOffsetSec = $maxAbs
    $result.Parsed = $true
    $result
}

#endregion

#region --- Helpers ---

function Invoke-ADHCExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutSeconds = 30
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = $tmpOut + '.err'

    try {
        $p = Start-Process -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr `
            -ErrorAction Stop

        $stdout = Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue

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

function Test-ADHCPrivateIPv4 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address)

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    $b = $ip.GetAddressBytes()
    if ($b[0] -eq 10) { return $true }
    if ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) { return $true }
    if ($b[0] -eq 192 -and $b[1] -eq 168) { return $true }
    return $false
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCTimeSynchronization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $domain   = $Context.Domain
    $localDc  = $env:COMPUTERNAME
    $results  = [System.Collections.Generic.List[object]]::new()
    $timeouts = (Get-ADHCDefaults).Connectivity.Timeouts

    Write-ADHCLog -Level Info -Message "TimeSynchronization: evaluating $localDc" -Logger $Context.Logger

    # Identify whether the local host is the PDC Emulator (single-DC and multi-DC aware).
    $pdcFqdn = $null
    if ($Context.FSMO -and $Context.FSMO.PDCEmulator) { $pdcFqdn = $Context.FSMO.PDCEmulator }
    $pdcShort = $null
    if ($pdcFqdn) { $pdcShort = ($pdcFqdn -split '\.')[0] }
    $isPdc = ($pdcShort -and ($pdcShort -ieq $localDc))

    # ------------------------------------------------------------------
    # 1) W32Time service state
    # ------------------------------------------------------------------
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $svc = $null; $svcErr = $null
    try { $svc = Get-Service -Name 'W32Time' -ErrorAction Stop } catch { $svcErr = $_.Exception.Message }
    $sw.Stop()

    if ($svcErr -or -not $svc) {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-W32TIME-SERVICE' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'FAIL' -Severity 'High' `
            -Title 'W32Time service not available' `
            -Description 'The W32Time service could not be queried.' `
            -Evidence @{ Error = $svcErr } `
            -PotentialImpact 'Without W32Time, the DC cannot maintain accurate time; Kerberos breaks beyond ~5min skew.' `
            -PossibleCauses @('Service removed','OS misconfiguration') `
            -RecommendedInvestigation @('Verify the W32Time service exists.') `
            -SuggestedCommands @('Get-Service W32Time','w32tm /register') `
            -Duration $sw.Elapsed -ToolUsed 'Get-Service'
        ))
    } elseif ($svc.Status -ne 'Running') {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-W32TIME-SERVICE' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'FAIL' -Severity 'High' `
            -Title "W32Time is $($svc.Status)" `
            -Description 'The W32Time service is not running.' `
            -Evidence @{ Service='W32Time'; Status=$svc.Status.ToString(); StartType=$svc.StartType.ToString() } `
            -PotentialImpact 'Time drift beyond 5 minutes breaks Kerberos authentication.' `
            -PossibleCauses @('Manual stop','Startup failure','Misconfiguration') `
            -RecommendedInvestigation @('Start the service and verify it stays running.') `
            -SuggestedCommands @('Start-Service W32Time','Get-Service W32Time') `
            -Duration $sw.Elapsed -ToolUsed 'Get-Service'
        ))
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-W32TIME-SERVICE' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'PASS' -Severity 'High' `
            -Title "W32Time running on $localDc" `
            -Description 'The W32Time service is running and set to Automatic.' `
            -Evidence @{ Status=$svc.Status.ToString(); StartType=$svc.StartType.ToString() } `
            -PotentialImpact 'No impact.' `
            -SuggestedCommands @('w32tm /query /status') `
            -Duration $sw.Elapsed -ToolUsed 'Get-Service'
        ))
    }

    # ------------------------------------------------------------------
    # 2) w32tm /query /status
    # ------------------------------------------------------------------
    $statusRaw = $null; $statusParsed = $null
    if ($Context.Capabilities.W32tm) {
        $run = Invoke-ADHCExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/query','/status') -TimeoutSeconds $timeouts.W32tm
        if ($run.Success -and $run.StdOut) {
            $statusRaw = $run.StdOut
            $statusParsed = ConvertFrom-ADHCW32tmStatus -RawOutput $statusRaw
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-SOURCE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'Critical' `
                -Title 'w32tm /query /status produced no output' `
                -Description 'Could not read the status of w32tm.' `
                -Evidence @{ Error=$run.Error; ExitCode=$run.ExitCode; StdErr=$run.StdErr } `
                -IsInconclusive $true -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-SOURCE' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'UNKNOWN' -Severity 'Critical' `
            -Title 'w32tm.exe not available' `
            -WasSkipped $true -SkipReason 'w32tm.exe not available'
        ))
    }

    # ------------------------------------------------------------------
    # 3) w32tm /query /configuration
    # ------------------------------------------------------------------
    $cfgRaw = $null; $cfgParsed = $null
    if ($Context.Capabilities.W32tm) {
        $run = Invoke-ADHCExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/query','/configuration') -TimeoutSeconds $timeouts.W32tm
        if ($run.Success -and $run.StdOut) {
            $cfgRaw = $run.StdOut
            $cfgParsed = ConvertFrom-ADHCW32tmConfiguration -RawOutput $cfgRaw
        }
    }

    # TIME-CONFIG-TYPE
    if ($cfgParsed -and $cfgParsed.Parsed) {
        $typeOk = ($cfgParsed.Type -eq 'NTP' -or $cfgParsed.Type -eq 'NT5DS')
        if ($cfgParsed.Type -eq 'NoSync') {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-CONFIG-TYPE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'FAIL' -Severity 'High' `
                -Title 'w32tm Type is NoSync' `
                -Description 'The DC is configured to not synchronize its clock.' `
                -Evidence @{ Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                -PotentialImpact 'Time drift over days; Kerberos and event correlation are affected.' `
                -PossibleCauses @('Manual registry edit','Legacy configuration') `
                -RecommendedInvestigation @('Set Type to NTP (PDC) or NT5DS (non-PDC).') `
                -SuggestedCommands @(
                    "w32tm /config /manualpeerlist:`"<server>`" /syncfromflags:manual /reliable:yes /update",
                    'w32tm /config /syncfromflags:domhier /update'
                ) `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        } elseif (-not $typeOk) {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-CONFIG-TYPE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'WARNING' -Severity 'High' `
                -Title "Unexpected w32tm Type: $($cfgParsed.Type)" `
                -Description 'Type is neither NTP nor NT5DS.' `
                -Evidence @{ Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                -PotentialImpact 'Time source may not be authoritative.' `
                -PossibleCauses @('Legacy or unusual configuration') `
                -RecommendedInvestigation @('Confirm intended Type.') `
                -SuggestedCommands @('w32tm /query /configuration') `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-CONFIG-TYPE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'PASS' -Severity 'High' `
                -Title "w32tm Type: $($cfgParsed.Type)" `
                -Description 'Type is within the expected set.' `
                -Evidence @{ Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @('w32tm /query /configuration') `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-CONFIG-TYPE' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'w32tm configuration could not be interpreted' `
            -Description 'The configuration output was not recognized.' `
            -Evidence @{ Raw=$cfgRaw } `
            -IsInconclusive $true -Duration ([TimeSpan]::Zero) -ToolUsed 'w32tm'
        ))
    }

    # TIME-PDC-EXPECTATION
    if ($cfgParsed -and $cfgParsed.Parsed) {
        if ($isPdc) {
            if ($cfgParsed.Type -eq 'NTP') {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-PDC-EXPECTATION' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'PASS' -Severity 'Medium' `
                    -Title 'PDC Emulator uses NTP' `
                    -Description 'PDC Emulator should sync with an external NTP source.' `
                    -Evidence @{ IsPdc=$true; Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                    -PotentialImpact 'No impact.' `
                    -SuggestedCommands @('w32tm /query /configuration') `
                    -ToolUsed 'w32tm'
                ))
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-PDC-EXPECTATION' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'WARNING' -Severity 'Medium' `
                    -Title "PDC Emulator uses $($cfgParsed.Type) instead of NTP" `
                    -Description 'The PDC Emulator is the authoritative time source; it should sync to an external NTP source.' `
                    -Evidence @{ IsPdc=$true; Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                    -PotentialImpact 'The domain may sync to a non-authoritative source.' `
                    -PossibleCauses @('Default domain hierarchy still in place') `
                    -RecommendedInvestigation @('Configure NTP with an authoritative external source.') `
                    -SuggestedCommands @("w32tm /config /manualpeerlist:`"pool.ntp.org`" /syncfromflags:manual /reliable:yes /update") `
                    -ToolUsed 'w32tm'
                ))
            }
        } else {
            if ($cfgParsed.Type -eq 'NT5DS' -or $cfgParsed.Type -eq 'NTP') {
                # Either is defensible in smaller domains; NTP is not ideal for non-PDC.
                $status = if ($cfgParsed.Type -eq 'NT5DS') { 'PASS' } else { 'INFO' }
                $title  = if ($cfgParsed.Type -eq 'NT5DS') { 'Non-PDC DC uses NT5DS' } else { 'Non-PDC DC uses NTP (allowed but unusual)' }
                $impact = if ($cfgParsed.Type -eq 'NT5DS') { 'No impact.' } else { 'Non-PDC using NTP may cause inconsistent time across DCs.' }
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-PDC-EXPECTATION' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status $status -Severity 'Medium' `
                    -Title $title `
                    -Description 'Non-PDC DC time configuration.' `
                    -Evidence @{ IsPdc=$false; Type=$cfgParsed.Type; NtpServer=$cfgParsed.NtpServer } `
                    -PotentialImpact $impact `
                    -SuggestedCommands @('w32tm /query /configuration') `
                    -ToolUsed 'w32tm'
                ))
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-PDC-EXPECTATION' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'WARNING' -Severity 'Medium' `
                    -Title "Non-PDC DC uses unexpected Type: $($cfgParsed.Type)" `
                    -Description 'Non-PDC DCs are expected to use NT5DS.' `
                    -Evidence @{ IsPdc=$false; Type=$cfgParsed.Type } `
                    -PotentialImpact 'Time may diverge across DCs.' `
                    -SuggestedCommands @('w32tm /config /syncfromflags:domhier /update') `
                    -ToolUsed 'w32tm'
                ))
            }
        }
    }

    # ------------------------------------------------------------------
    # 4) TIME-SOURCE and TIME-STRATUM from status
    # ------------------------------------------------------------------
    if ($statusParsed -and $statusParsed.Parsed) {
        $source = $statusParsed.Source
        $sourceIsLocalClock = $false
        if ($source) {
            $srcLower = $source.ToLowerInvariant()
            if ($srcLower -match 'local\s*cmos|rel.ggio\s*cmos' -or $srcLower -match 'free-running') {
                $sourceIsLocalClock = $true
            }
        }

        if ($sourceIsLocalClock -or -not $source) {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-SOURCE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'FAIL' -Severity 'Critical' `
                -Title 'DC time source is the local CMOS clock' `
                -Description 'The DC is not synchronizing to a reliable time source.' `
                -Evidence @{ Source=$source; Stratum=$statusParsed.Stratum; LeapIndicator=$statusParsed.LeapIndicator } `
                -PotentialImpact 'Time will drift; Kerberos will fail once skew exceeds tolerance.' `
                -PossibleCauses @('No NTP peers reachable','Configuration reset','Service restarted without sync') `
                -RecommendedInvestigation @('Check reachability of the configured NTP source; re-run w32tm /resync.') `
                -SuggestedCommands @('w32tm /query /source','w32tm /resync /force') `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        } elseif ($source -match '^\d+\.\d+\.\d+\.\d+$' -and (Test-ADHCPrivateIPv4 -Address $source)) {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-SOURCE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'INFO' -Severity 'Informational' `
                -Title "Time source is a private IP: $source" `
                -Description 'Source is an RFC1918 address. Ensure it is a trusted time server.' `
                -Evidence @{ Source=$source; IsPrivateIPv4=$true; Stratum=$statusParsed.Stratum } `
                -PotentialImpact 'No impact if the address is a trusted NTP server.' `
                -PossibleCauses @('Internal NTP server','Router providing time') `
                -RecommendedInvestigation @('Confirm the source is a reliable NTP server.') `
                -SuggestedCommands @("w32tm /stripchart /computer:$source /samples:2 /dataonly") `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-SOURCE' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'PASS' -Severity 'Critical' `
                -Title "Time source: $source" `
                -Description 'DC synchronizes to a non-local time source.' `
                -Evidence @{ Source=$source; Stratum=$statusParsed.Stratum } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @('w32tm /query /source') `
                -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        }

        # TIME-STRATUM
        if ($null -ne $statusParsed.Stratum) {
            if ($statusParsed.Stratum -ge 16) {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-STRATUM' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'FAIL' -Severity 'High' `
                    -Title 'Time Stratum is 16 (unsynchronized)' `
                    -Description 'Stratum 16 means the clock is unsynchronized.' `
                    -Evidence @{ Stratum=$statusParsed.Stratum; Source=$statusParsed.Source } `
                    -PotentialImpact 'Kerberos and time-based operations are unreliable.' `
                    -RecommendedInvestigation @('Fix the time source configuration.') `
                    -SuggestedCommands @('w32tm /query /source','w32tm /resync /force') `
                    -Duration $run.Duration -ToolUsed 'w32tm'
                ))
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-STRATUM' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'PASS' -Severity 'High' `
                    -Title "Time Stratum: $($statusParsed.Stratum)" `
                    -Description 'Stratum is within the synchronized range (<16).' `
                    -Evidence @{ Stratum=$statusParsed.Stratum } `
                    -PotentialImpact 'No impact.' `
                    -SuggestedCommands @('w32tm /query /status') `
                    -Duration $run.Duration -ToolUsed 'w32tm'
                ))
            }
        }

        # TIME-LAST-SYNC
        if ($statusParsed.LastSuccessSync) {
            $parsedDate = $null
            foreach ($fmt in @('dd/MM/yyyy HH:mm:ss','MM/dd/yyyy HH:mm:ss','dd/MM/yyyy hh:mm:ss tt','MM/dd/yyyy hh:mm:ss tt')) {
                try {
                    $parsedDate = [datetime]::ParseExact($statusParsed.LastSuccessSync, $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
                    break
                } catch { }
            }
            if ($parsedDate) {
                $hoursSince = ((Get-Date) - $parsedDate).TotalHours
                if ($hoursSince -gt 24) {
                    $results.Add((New-CheckResult `
                        -CheckId 'TIME-LAST-SYNC' -Category 'TimeSynchronization' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'WARNING' -Severity 'Medium' `
                        -Title "Last successful sync was $([int]$hoursSince)h ago" `
                        -Description 'Time has not been synchronized in over 24 hours.' `
                        -Evidence @{ LastSyncRaw=$statusParsed.LastSuccessSync; HoursSince=[math]::Round($hoursSince,1) } `
                        -PotentialImpact 'Clock drift may accumulate; Kerberos tolerance is 5 minutes by default.' `
                        -PossibleCauses @('NTP source unreachable','Poll interval too long','Recent reboot') `
                        -RecommendedInvestigation @('Check NTP source reachability; consider resync.') `
                        -SuggestedCommands @('w32tm /resync /force','w32tm /query /status') `
                        -Duration $run.Duration -ToolUsed 'w32tm'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'TIME-LAST-SYNC' -Category 'TimeSynchronization' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'PASS' -Severity 'Medium' `
                        -Title "Last successful sync: $($statusParsed.LastSuccessSync)" `
                        -Description 'Last sync within the last 24 hours.' `
                        -Evidence @{ LastSyncRaw=$statusParsed.LastSuccessSync; HoursSince=[math]::Round($hoursSince,1) } `
                        -PotentialImpact 'No impact.' `
                        -SuggestedCommands @('w32tm /query /status') `
                        -Duration $run.Duration -ToolUsed 'w32tm'
                    ))
                }
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-LAST-SYNC' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'UNKNOWN' -Severity 'Medium' `
                    -Title 'Last successful sync time could not be parsed' `
                    -Description 'Unexpected date format.' `
                    -Evidence @{ LastSyncRaw=$statusParsed.LastSuccessSync } `
                    -IsInconclusive $true -ToolUsed 'w32tm'
                ))
            }
        }
    }

    # ------------------------------------------------------------------
    # 5) TIME-PEERS
    # ------------------------------------------------------------------
    $peersParsed = $null
    if ($Context.Capabilities.W32tm) {
        $run = Invoke-ADHCExternalCommand -FilePath 'w32tm.exe' -ArgumentList @('/query','/peers') -TimeoutSeconds $timeouts.W32tm
        if ($run.Success -and $run.StdOut) {
            $peersParsed = ConvertFrom-ADHCW32tmPeers -RawOutput $run.StdOut
        }
    }

    if ($peersParsed -and $peersParsed.Parsed) {
        $active = @($peersParsed.Peers | Where-Object { $_.State -and ($_.State.ToLower() -match 'ativo|active') })
        if ($active.Count -gt 0) {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-PEERS' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'PASS' -Severity 'Medium' `
                -Title "$($active.Count) active time peer(s)" `
                -Description 'At least one peer is active.' `
                -Evidence @{ Peers=$peersParsed.Peers; ActiveCount=$active.Count } `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @('w32tm /query /peers') `
                -ToolUsed 'w32tm'
            ))
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-PEERS' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'WARNING' -Severity 'Medium' `
                -Title 'No active time peers' `
                -Description 'Peers are configured but none are active.' `
                -Evidence @{ Peers=$peersParsed.Peers } `
                -PotentialImpact 'Time may not be synchronized.' `
                -PossibleCauses @('NTP server unreachable','Wrong peer list') `
                -RecommendedInvestigation @('Verify NTP source reachability.') `
                -SuggestedCommands @('w32tm /query /peers','w32tm /resync /force') `
                -ToolUsed 'w32tm'
            ))
        }
    } elseif ($peersParsed) {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-PEERS' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'No time peers configured' `
            -Description 'w32tm returned no peers. This is expected for a domain member using NT5DS.' `
            -Evidence @{ Peers=@() } `
            -PotentialImpact 'No impact in a domain hierarchy.' `
            -SuggestedCommands @('w32tm /query /peers') `
            -ToolUsed 'w32tm'
        ))
    }

    # ------------------------------------------------------------------
    # 6) TIME-OFFSET via stripchart against the configured source
    # ------------------------------------------------------------------
    if ($statusParsed -and $statusParsed.Source -and $statusParsed.Source -notmatch 'local\s*cmos|rel.ggio\s*cmos') {
        $target = $statusParsed.Source
        $run = Invoke-ADHCExternalCommand -FilePath 'w32tm.exe' `
            -ArgumentList @('/stripchart', "/computer:$target", '/samples:2', '/dataonly') `
            -TimeoutSeconds 15

        if ($run.Success -and $run.StdOut) {
            $offset = ConvertFrom-ADHCW32tmStripchart -RawOutput $run.StdOut
            if ($offset.Parsed) {
                $maxOffset = [double]$offset.MaxOffsetSec
                if ($maxOffset -gt 5) {
                    $results.Add((New-CheckResult `
                        -CheckId 'TIME-OFFSET' -Category 'TimeSynchronization' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'FAIL' -Severity 'High' `
                        -Title ("Time offset vs source is {0:N3}s" -f $maxOffset) `
                        -Description 'Offset is above the 5-second threshold.' `
                        -Evidence @{ Source=$target; Samples=$offset.Samples; MaxOffsetSec=$maxOffset } `
                        -PotentialImpact 'Kerberos tolerates up to ~5 minutes by default, but drift this large is suspicious.' `
                        -PossibleCauses @('Drifted clock','NTP source unreachable','Wrong source') `
                        -RecommendedInvestigation @('Resync against source; verify source is authoritative.') `
                        -SuggestedCommands @('w32tm /resync /force', "w32tm /stripchart /computer:$target /samples:5") `
                        -Duration $run.Duration -ToolUsed 'w32tm'
                    ))
                } else {
                    $results.Add((New-CheckResult `
                        -CheckId 'TIME-OFFSET' -Category 'TimeSynchronization' `
                        -Domain $domain -DomainController $localDc -ComputerName $localDc `
                        -Status 'PASS' -Severity 'High' `
                        -Title ("Time offset vs source is {0:N3}s" -f $maxOffset) `
                        -Description 'Offset is within tolerance.' `
                        -Evidence @{ Source=$target; Samples=$offset.Samples; MaxOffsetSec=$maxOffset } `
                        -PotentialImpact 'No impact.' `
                        -SuggestedCommands @('w32tm /stripchart') `
                        -Duration $run.Duration -ToolUsed 'w32tm'
                    ))
                }
            } else {
                $results.Add((New-CheckResult `
                    -CheckId 'TIME-OFFSET' -Category 'TimeSynchronization' `
                    -Domain $domain -DomainController $localDc -ComputerName $localDc `
                    -Status 'UNKNOWN' -Severity 'High' `
                    -Title 'Time offset could not be determined' `
                    -Description 'stripchart output was not recognized.' `
                    -Evidence @{ Raw=$run.StdOut } `
                    -IsInconclusive $true -Duration $run.Duration -ToolUsed 'w32tm'
                ))
            }
        } else {
            $results.Add((New-CheckResult `
                -CheckId 'TIME-OFFSET' -Category 'TimeSynchronization' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'High' `
                -Title 'stripchart could not run' `
                -Description 'w32tm /stripchart failed or timed out.' `
                -Evidence @{ Error=$run.Error; StdErr=$run.StdErr; Source=$target } `
                -IsInconclusive $true -Duration $run.Duration -ToolUsed 'w32tm'
            ))
        }
    } else {
        $results.Add((New-CheckResult `
            -CheckId 'TIME-OFFSET' -Category 'TimeSynchronization' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'UNKNOWN' -Severity 'High' `
            -Title 'Time offset check skipped' `
            -Description 'No usable source to measure against.' `
            -WasSkipped $true -SkipReason 'No usable source'
        ))
    }

    # ------------------------------------------------------------------
    # 7) Parser recognition marker
    # ------------------------------------------------------------------
    $parseOk = ($statusParsed -and $statusParsed.Parsed) -or ($cfgParsed -and $cfgParsed.Parsed) -or ($peersParsed -and $peersParsed.Parsed)
    $parseStatus = 'UNKNOWN'
    if ($parseOk) { $parseStatus = 'PASS' }

    $statusNotes = @()
    if ($statusParsed) { $statusNotes = $statusParsed.Notes }
    $configNotes = @()
    if ($cfgParsed)    { $configNotes = $cfgParsed.Notes }
    $peersNotes  = @()
    if ($peersParsed)  { $peersNotes  = $peersParsed.Notes }

    $evidence = @{
        StatusParsed = ($statusParsed -and $statusParsed.Parsed)
        ConfigParsed = ($cfgParsed -and $cfgParsed.Parsed)
        PeersParsed  = ($peersParsed -and $peersParsed.Parsed)
        StatusNotes  = $statusNotes
        ConfigNotes  = $configNotes
        PeersNotes   = $peersNotes
    }

    $results.Add((New-CheckResult `
        -CheckId 'TIME-W32TM-PARSE' -Category 'TimeSynchronization' `
        -Domain $domain -DomainController $localDc -ComputerName $localDc `
        -Status $parseStatus `
        -Severity 'Informational' `
        -Title 'w32tm output interpreted' `
        -Description 'Reports whether the w32tm parsers recognized the output.' `
        -Evidence $evidence `
        -IsInconclusive (-not $parseOk) `
        -ToolUsed 'w32tm'
    ))

    $results.ToArray()
}

#endregion