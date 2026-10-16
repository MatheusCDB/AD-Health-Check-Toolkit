Set-StrictMode -Version Latest

#region --- Helpers ---

function Get-ADHCEventLevelName {
    <#
    .SYNOPSIS
        Maps a Windows event Level value to a stable English name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Level)
    switch ($Level) {
        1 { 'Critical' }
        2 { 'Error'    }
        3 { 'Warning'  }
        4 { 'Information' }
        5 { 'Verbose'  }
        default { 'Unknown' }
    }
}

function Get-ADHCEventSummaryForLog {
    <#
    .SYNOPSIS
        Queries a single event log for significant events in the last N days
        and returns a structured summary grouped by Id + Level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogName,
        [Parameter(Mandatory)][int]$LookbackDays,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$SignificantIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$AcceptableIds,
        [AllowEmptyCollection()][int[]]$ExtraIds = @()
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = [PSCustomObject]@{
        Success        = $false
        LogName        = $LogName
        TotalCount     = 0
        HashtableOk    = $false
        Warnings       = @()
        Errors         = @()
        Acceptable     = @()
        Error          = $null
        Duration       = [TimeSpan]::Zero
    }

    try {
        # Union of significant + extra (Security) + acceptable so we can classify everything in one pass.
        $idSet = New-Object System.Collections.Generic.HashSet[int]
        foreach ($id in $SignificantIds) { [void]$idSet.Add($id) }
        foreach ($id in $ExtraIds)       { [void]$idSet.Add($id) }
        foreach ($id in $AcceptableIds)  { [void]$idSet.Add($id) }
        if ($idSet.Count -eq 0) {
            $result.Success = $true
            $result.Duration = $sw.Elapsed
            return $result
        }

        $filter = @{
            LogName   = $LogName
            StartTime = (Get-Date).AddDays(-1 * $LookbackDays)
            Id        = @($idSet)
        }

        try {
            $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop
            $result.HashtableOk = $true
        } catch [Exception] {
            # No events at all is expected for quiet logs.
            if ($_.Exception.Message -match 'No events were found') {
                $events = @()
                $result.HashtableOk = $true
            } else {
                $result.Error = $_.Exception.Message
                $result.Duration = $sw.Elapsed
                return $result
            }
        }

        $events = @($events)
        $result.TotalCount = $events.Count

        $groups = @{}
        foreach ($e in $events) {
            $key = "{0}|{1}" -f [int]$e.Id, [int]$e.Level
            if (-not $groups.ContainsKey($key)) {
                $groups[$key] = [System.Collections.Generic.List[object]]::new()
            }
            $groups[$key].Add($e)
        }

        $acceptableSet = New-Object System.Collections.Generic.HashSet[int]
        foreach ($id in $AcceptableIds) { [void]$acceptableSet.Add($id) }

        foreach ($key in $groups.Keys) {
            $parts = $key.Split('|')
            $id    = [int]$parts[0]
            $level = [int]$parts[1]
            $bucket = $groups[$key]

            $sample = $bucket[0]
            $sampleMsg = ''
            try { $sampleMsg = ($sample.Message -split "`r?`n")[0] } catch { }
            $entry = [PSCustomObject]@{
                Id            = $id
                Level         = $level
                LevelName     = Get-ADHCEventLevelName -Level $level
                Count         = $bucket.Count
                Provider      = $sample.ProviderName
                FirstTime     = ($bucket | Measure-Object -Property TimeCreated -Minimum).Minimum
                LastTime      = ($bucket | Measure-Object -Property TimeCreated -Maximum).Maximum
                SampleMessage = $sampleMsg
            }

            if ($acceptableSet.Contains($id)) {
                $result.Acceptable += $entry
            } elseif ($level -eq 3) {
                $result.Warnings += $entry
            } elseif ($level -eq 1 -or $level -eq 2) {
                $result.Errors += $entry
            }
            # Levels 4/5 (Information/Verbose) fall into nothing.
        }

        $result.Success  = $true
        $result.Duration = $sw.Elapsed
        return $result
    } catch {
        $result.Error = $_.Exception.Message
        $result.Duration = $sw.Elapsed
        return $result
    } finally {
        $sw.Stop()
    }
}

function ConvertTo-ADHCEventEvidence {
    <#
    .SYNOPSIS
        Renders a summary row for evidence output, capped for size.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [int]$MaxEntries = 25
    )
    $out = foreach ($e in ($Entries | Select-Object -First $MaxEntries)) {
        [PSCustomObject]@{
            Id        = $e.Id
            Level     = $e.LevelName
            Count     = $e.Count
            Provider  = $e.Provider
            FirstTime = $e.FirstTime
            LastTime  = $e.LastTime
            Sample    = $e.SampleMessage
        }
    }
    ,@($out)
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCEventLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $defaults = Get-ADHCDefaults
    $evtCfg   = $defaults.EventLogs
    $domain   = $Context.Domain
    $localDc  = $env:COMPUTERNAME
    $lookback = [int]$Context.EventLookbackDays
    $includeSecurity = [bool]$Context.IncludeSecurityLog

    $results = [System.Collections.Generic.List[object]]::new()

    Write-ADHCLog -Level Info -Message "EventLogs: evaluating $localDc (lookback=${lookback}d)" -Logger $Context.Logger

    # --- Optional Security log (opt-in) ---
    $logsToScan = @($evtCfg.DefaultLogs)
    if ($includeSecurity) { $logsToScan += 'Security' }

    foreach ($logName in $logsToScan) {
        $isSecurity = ($logName -ieq 'Security')

        $significant = @()
        $acceptable  = @()
        $extraIds    = @()

        if (-not $isSecurity) {
            if ($evtCfg.SignificantIds.ContainsKey($logName)) { $significant = @($evtCfg.SignificantIds[$logName]) }
            if ($evtCfg.AcceptableIds.ContainsKey($logName))  { $acceptable  = @($evtCfg.AcceptableIds[$logName])  }
        } else {
            $extraIds = @($evtCfg.SecurityIds)
        }

        $checkId = 'EVT-{0}' -f ($logName -replace '[^A-Za-z0-9]','-').ToUpperInvariant()

        $summary = Get-ADHCEventSummaryForLog `
            -LogName         $logName `
            -LookbackDays    $lookback `
            -SignificantIds  $significant `
            -AcceptableIds   $acceptable `
            -ExtraIds        $extraIds

        if (-not $summary.Success) {
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'EventLogs' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "Could not query log '$logName'" `
                -Description 'Get-WinEvent failed for this log.' `
                -Evidence @{ LogName=$logName; Error=$summary.Error } `
                -IsInconclusive $true -Duration $summary.Duration -ToolUsed 'Get-WinEvent'
            ))
            continue
        }

        $errorCount    = 0
        foreach ($e in $summary.Errors)   { $errorCount   += $e.Count }
        $warningCount  = 0
        foreach ($e in $summary.Warnings) { $warningCount += $e.Count }
        $acceptableCount = 0
        foreach ($e in $summary.Acceptable) { $acceptableCount += $e.Count }

        $recurrenceThreshold = [int]$evtCfg.RecurrenceThreshold
        $warningBulk         = [int]$evtCfg.WarningBulkThreshold

        $hasRecurring = $false
        foreach ($e in $summary.Errors) {
            if ($e.Count -ge $recurrenceThreshold) { $hasRecurring = $true; break }
        }

        $status   = 'PASS'
        $severity = 'High'
        $title    = "No significant events in '$logName' (${lookback}d)"

        if ($summary.Errors.Count -gt 0) {
            if ($hasRecurring) {
                $status   = 'FAIL'
                $severity = 'High'
                $title    = "Recurring errors in '$logName' (${errorCount} total)"
            } else {
                $status   = 'WARNING'
                $severity = 'Medium'
                $title    = "Isolated errors in '$logName' (${errorCount} total)"
            }
        } elseif ($summary.Warnings.Count -gt 0) {
            if ($warningCount -ge $warningBulk) {
                $status   = 'WARNING'
                $severity = 'Low'
                $title    = "Bulk warnings in '$logName' (${warningCount} total)"
            } else {
                $status   = 'INFO'
                $severity = 'Informational'
                $title    = "Warnings only in '$logName' (${warningCount} total)"
            }
        }

        $evidence = @{
            LogName              = $logName
            LookbackDays         = $lookback
            TotalMatched         = $summary.TotalCount
            ErrorCount           = $errorCount
            WarningCount         = $warningCount
            AcceptableCount      = $acceptableCount
            Errors               = ConvertTo-ADHCEventEvidence -Entries $summary.Errors
            Warnings             = ConvertTo-ADHCEventEvidence -Entries $summary.Warnings
            AcceptableSuppressed = ConvertTo-ADHCEventEvidence -Entries $summary.Acceptable
            SignificantIds       = $significant
            AcceptableIds        = $acceptable
        }

        $impact = 'No impact.'
        if ($status -eq 'FAIL') {
            $impact = 'Recurring errors in this log indicate a persistent issue that should be investigated.'
        } elseif ($status -eq 'WARNING') {
            $impact = 'A small number of errors or bulk warnings detected; verify if they are transient.'
        }

        $causes = @('Service or driver issue','Network or DNS problem','Configuration drift','Dependency unavailable')
        if ($logName -ieq 'DFS Replication') {
            $causes = @('SYSVOL replication disabled or stale','Partner unreachable','Configuration drift (e.g., MaxOfflineTimeInDays)')
        } elseif ($logName -ieq 'Directory Service') {
            $causes = @('Replication error','LDAP issue','Machine account problem','Schema or config drift')
        } elseif ($logName -ieq 'DNS Server') {
            $causes = @('Zone transfer issue','Dynamic update failure','DNSSEC validation failure','Scavenging problem')
        } elseif ($logName -ieq 'System') {
            $causes = @('Driver failure','Service crash','Network stack issue','Kernel-level problem')
        } elseif ($logName -ieq 'Security') {
            $causes = @('Failed authentication attempt','Account lockout','Kerberos/NTLM issue','Directory Services access problem')
        }

        $cmd = @("Get-WinEvent -FilterHashtable @{ LogName='$logName'; StartTime=(Get-Date).AddDays(-$lookback); Level=1,2 } | Select-Object -First 50")

        $results.Add((New-CheckResult `
            -CheckId $checkId -Category 'EventLogs' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status $status -Severity $severity `
            -Title $title `
            -Description "Summary of significant events in the '$logName' log for the last $lookback day(s)." `
            -Evidence $evidence `
            -PotentialImpact $impact `
            -PossibleCauses $causes `
            -RecommendedInvestigation @("Review the Evidence.Errors list.", "Check the affected component's logs and services.") `
            -SuggestedCommands $cmd `
            -Duration $summary.Duration -ToolUsed 'Get-WinEvent'
        ))
    }

    # --- Security log skipped marker ---
    if (-not $includeSecurity) {
        $results.Add((New-CheckResult `
            -CheckId 'EVT-SECURITY-SKIPPED' -Category 'EventLogs' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'INFO' -Severity 'Informational' `
            -Title 'Security log collection skipped' `
            -Description 'Pass -IncludeSecurityLog to include a curated subset of Security events.' `
            -Evidence @{ Reason='Opt-in required'; Flag='-IncludeSecurityLog' } `
            -PotentialImpact 'No impact.' `
            -ToolUsed 'Aggregate'
        ))
    }

    # --- Parse coverage marker ---
    $parseOk = $true
    foreach ($r in $results) {
        if ($r.Status -eq 'UNKNOWN' -and $r.Category -eq 'EventLogs') { $parseOk = $false; break }
    }
    $parseStatus = 'UNKNOWN'
    if ($parseOk) { $parseStatus = 'PASS' }

    $results.Add((New-CheckResult `
        -CheckId 'EVT-PARSE' -Category 'EventLogs' `
        -Domain $domain -DomainController $localDc -ComputerName $localDc `
        -Status $parseStatus -Severity 'Informational' `
        -Title 'Event log query coverage' `
        -Description 'Reports whether all scanned logs were queried successfully.' `
        -Evidence @{ Scanned = @($logsToScan); IncludeSecurity = $includeSecurity } `
        -IsInconclusive (-not $parseOk) `
        -ToolUsed 'Aggregate'
    ))

    $results.ToArray()
}

#endregion