Set-StrictMode -Version Latest

#region --- Parser: dcdiag /test:X single-test output (pt-BR / en-US) ---

function ConvertFrom-ADHCDcdiagSingleTest {
    <#
    .SYNOPSIS
        Parses the output of a single `dcdiag /test:X` invocation.

    .DESCRIPTION
        dcdiag prints a lot of setup noise before the actual verdict.
        The verdict line has one of these shapes:

            ......................... AD02 passou no teste Advertising
            ......................... AD02 falhou no teste Advertising
            ......................... crg.local passou no teste FsmoCheck
            ......................... DC01 passed test Advertising
            ......................... DC01 failed test Advertising

        "Unknown" verdicts are also possible for some tests:
            ......................... AD02 não passou no teste <Name>
            ......................... DC01 did not pass test <Name>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestName,
        [Parameter(Mandatory)][AllowNull()][string]$RawOutput
    )

    $result = [PSCustomObject]@{
        Parsed       = $false
        Verdict      = $null          # 'PASS' | 'FAIL' | 'UNKNOWN' | $null
        Target       = $null          # DC or domain short name mentioned in the verdict
        RawTail      = $null          # the verdict line, for evidence
        Notes        = @()
    }

    if (-not $RawOutput) {
        $result.Notes += 'Empty output.'
        return $result
    }

    $lines = $RawOutput -split "`r?`n"
    $verdictLine = $null

    # Scan from the bottom, first match wins (verdict is always near the end).
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ($line -match ('\.{3,}\s+(\S+)\s+(passou no teste|falhou no teste|n.o passou no teste)\s+' + [regex]::Escape($TestName))) {
            $verdictLine = $line.Trim()
            $result.Target = $Matches[1]
            switch -Regex ($Matches[2]) {
                '^passou no teste'    { $result.Verdict = 'PASS' }
                '^falhou no teste'    { $result.Verdict = 'FAIL' }
                '^n.o passou no teste' { $result.Verdict = 'UNKNOWN' }
            }
            break
        }
        if ($line -match ('\.{3,}\s+(\S+)\s+(passed|failed|did not pass)\s+test\s+' + [regex]::Escape($TestName))) {
            $verdictLine = $line.Trim()
            $result.Target = $Matches[1]
            switch -Regex ($Matches[2]) {
                '^passed'         { $result.Verdict = 'PASS' }
                '^failed'         { $result.Verdict = 'FAIL' }
                '^did not pass'   { $result.Verdict = 'UNKNOWN' }
            }
            break
        }
    }

    if ($verdictLine) {
        $result.Parsed  = $true
        $result.RawTail = $verdictLine
    } else {
        $result.Notes += "Verdict line for test '$TestName' not found."
    }

    $result
}

#endregion

#region --- Helpers ---

function Invoke-ADHCDcdiagTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestName,
        [int]$TimeoutSeconds = 60
    )

    $exe = Join-Path $env:SystemRoot 'System32\dcdiag.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = $null
            StdOut   = $null
            StdErr   = $null
            Duration = [TimeSpan]::Zero
            Error    = "dcdiag.exe not found at $exe"
        }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = $tmpOut + '.err'

    try {
        $p = Start-Process -FilePath $exe `
            -ArgumentList @("/test:$TestName") `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr `
            -ErrorAction Stop

        # dcdiag writes to the OEM code page (CP-850 on Windows pt-BR).
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

function Get-ADHCDcdiagFailureExcerpt {
    <#
    .SYNOPSIS
        Extracts up to N non-empty lines around a failed verdict for evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][string]$RawOutput,
        [int]$MaxLines = 15
    )
    if (-not $RawOutput) { return @() }
    $lines = $RawOutput -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
    if ($lines.Count -le $MaxLines) { return $lines }
    return ($lines | Select-Object -Last $MaxLines)
}

#endregion

#region --- Main entry point ---

function Invoke-ADHCDcdiag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $defaults = Get-ADHCDefaults
    $tests    = $defaults.Dcdiag.Tests
    $timeout  = $defaults.Connectivity.Timeouts.DcdiagPerTest
    $domain   = $Context.Domain
    $localDc  = $env:COMPUTERNAME

    $results = [System.Collections.Generic.List[object]]::new()

    Write-ADHCLog -Level Info -Message "DCDiag: evaluating $localDc ($($tests.Count) tests)" -Logger $Context.Logger

    # Capability gate.
    $exe = Join-Path $env:SystemRoot 'System32\dcdiag.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $results.Add((New-CheckResult `
            -CheckId 'DCDIAG-NOT-RUNNING' -Category 'DCDiag' `
            -Domain $domain -DomainController $localDc -ComputerName $localDc `
            -Status 'UNKNOWN' -Severity 'Medium' `
            -Title 'dcdiag.exe not available' `
            -Description "Expected at $exe." `
            -Evidence @{ ExpectedPath = $exe } `
            -WasSkipped $true -SkipReason 'dcdiag.exe not available'
        ))
        return $results.ToArray()
    }

    $parsedCount = 0
    $totalCount  = 0

    foreach ($t in $tests) {
        $name = $t.Name
        $checkId = "DCDIAG-{0}" -f $name.ToUpperInvariant()
        $totalCount++

        Write-ADHCLog -Level Info -Message "DCDiag: running /test:$name" -Logger $Context.Logger

        $run = Invoke-ADHCDcdiagTest -TestName $name -TimeoutSeconds $timeout
        $parsed = $null
        if ($run.Success -and $run.StdOut) {
            $parsed = ConvertFrom-ADHCDcdiagSingleTest -TestName $name -RawOutput $run.StdOut
        }

        $evidence = @{
            TestName      = $name
            ExitCode      = $run.ExitCode
            DurationSec   = [math]::Round($run.Duration.TotalSeconds, 2)
            VerdictTarget = if ($parsed) { $parsed.Target } else { $null }
            VerdictLine   = if ($parsed) { $parsed.RawTail } else { $null }
        }

        if (-not $run.Success) {
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'DCDiag' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity ($t.Severity) `
                -Title "dcdiag /test:$name did not complete" `
                -Description 'The dcdiag invocation failed to run.' `
                -Evidence (@{ TestName = $name; Error = $run.Error }) `
                -IsInconclusive $true -Duration $run.Duration -ToolUsed 'dcdiag'
            ))
            continue
        }

        if (-not $parsed -or -not $parsed.Parsed) {
            $notes = @()
            if ($parsed) { $notes = $parsed.Notes }
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'DCDiag' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'UNKNOWN' -Severity ($t.Severity) `
                -Title "dcdiag /test:$name verdict not recognized" `
                -Description 'dcdiag produced output but the verdict line could not be parsed.' `
                -Evidence (@{ TestName = $name; Notes = $notes; Excerpt = (Get-ADHCDcdiagFailureExcerpt -RawOutput $run.StdOut -MaxLines 10) }) `
                -IsInconclusive $true -Duration $run.Duration -ToolUsed 'dcdiag'
            ))
            continue
        }

        $parsedCount++

        $status = $parsed.Verdict
        if ($status -eq 'PASS') {
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'DCDiag' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'PASS' -Severity ($t.Severity) `
                -Title "dcdiag /test:$name passed" `
                -Description 'The test reported success.' `
                -Evidence $evidence `
                -PotentialImpact 'No impact.' `
                -SuggestedCommands @("dcdiag /test:$name /v") `
                -Duration $run.Duration -ToolUsed 'dcdiag'
            ))
        } elseif ($status -eq 'FAIL') {
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'DCDiag' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'FAIL' -Severity ($t.Severity) `
                -Title "dcdiag /test:$name FAILED" `
                -Description 'The test reported a failure.' `
                -Evidence (@{ TestName=$name; ExitCode=$run.ExitCode; VerdictLine=$parsed.RawTail; Excerpt=(Get-ADHCDcdiagFailureExcerpt -RawOutput $run.StdOut) }) `
                -PotentialImpact 'This test covers an essential AD DS function; investigate failures before proceeding.' `
                -PossibleCauses @('DNS resolution issue','Network or firewall issue','Service stopped','Configuration drift') `
                -RecommendedInvestigation @("Review dcdiag /test:$name /v output line by line.") `
                -SuggestedCommands @("dcdiag /test:$name /v") `
                -Duration $run.Duration -ToolUsed 'dcdiag'
            ))
        } else {
            # UNKNOWN verdict (e.g. "não passou no teste")
            $results.Add((New-CheckResult `
                -CheckId $checkId -Category 'DCDiag' `
                -Domain $domain -DomainController $localDc -ComputerName $localDc `
                -Status 'WARNING' -Severity ($t.Severity) `
                -Title "dcdiag /test:$name returned an inconclusive verdict" `
                -Description 'dcdiag reported that it did not fully pass the test.' `
                -Evidence $evidence `
                -PotentialImpact 'The test may indicate a pending issue or dependency.' `
                -RecommendedInvestigation @("Review dcdiag /test:$name /v output.") `
                -SuggestedCommands @("dcdiag /test:$name /v") `
                -Duration $run.Duration -ToolUsed 'dcdiag'
            ))
        }
    }

    # Parser summary marker.
    $parseRatio = 0
    if ($totalCount -gt 0) { $parseRatio = [double]$parsedCount / $totalCount }
    $parseOk = ($parseRatio -ge 0.8)
    $parseStatus = 'UNKNOWN'
    if ($parseOk) { $parseStatus = 'PASS' }

    $results.Add((New-CheckResult `
        -CheckId 'DCDIAG-PARSE' -Category 'DCDiag' `
        -Domain $domain -DomainController $localDc -ComputerName $localDc `
        -Status $parseStatus -Severity 'Informational' `
        -Title 'dcdiag verdict parser coverage' `
        -Description 'Reports what fraction of dcdiag tests produced a recognized verdict.' `
        -Evidence @{ Parsed = $parsedCount; Total = $totalCount; Ratio = [math]::Round($parseRatio, 2) } `
        -IsInconclusive (-not $parseOk) `
        -ToolUsed 'dcdiag'
    ))

    $results.ToArray()
}

#endregion