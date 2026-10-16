Set-StrictMode -Version Latest

function Invoke-ADHCAssessment {
    <#
    .SYNOPSIS
        Runs a full assessment and returns a consolidated result.
        This is the single entry point used by both the classic CLI
        and (later) the interactive TUI.

    .DESCRIPTION
        The function performs: output setup, logging, discovery, category
        orchestration, consolidation, scoring, and report generation.
        Optional callbacks allow the TUI to display progress.

    .OUTPUTS
        ADHC.AssessmentResult
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities,

        [string]$Domain,
        [string[]]$DomainController,
        [string]$OutputPath,
        [string[]]$Checks,

        [int]$EventLookbackDays = 7,
        [bool]$IncludeEventLogs = $false,
        [bool]$IncludeSecurityLog = $false,
        [bool]$IncludeDnsDetails = $false,
        [bool]$IncludeDcdiag = $false,
        [bool]$IncludeTopology = $false,
        [bool]$IncludeGroupPolicy = $false,
        [bool]$SkipPing = $false,

        [PSCredential]$Credential,
        [int]$ThrottleLimit = 5,
        [bool]$NoReport = $false,
        [ValidateSet('HTML','JSON','CSV')]
        [string[]]$ReportFormat = @('HTML','JSON','CSV'),

        # Optional callbacks for TUI integration.
        [scriptblock]$OnDiscoveryDone,
        [scriptblock]$OnCategoryStart,
        [scriptblock]$OnCategoryEnd,
        [scriptblock]$OnReportGenerated
    )

    $startedAt = (Get-Date).ToUniversalTime()

    # ------------------------------------------------------------------
    # Output path
    # ------------------------------------------------------------------
    if (-not $OutputPath) {
        $OutputPath = Join-Path $ScriptRoot ("Reports/" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path

    # ------------------------------------------------------------------
    # Logger
    # ------------------------------------------------------------------
    $logger = Initialize-ADHCLog -LogDirectory $OutputPath -ToolVersion $ToolVersion

    # ------------------------------------------------------------------
    # Run metadata
    # ------------------------------------------------------------------
    $runMetadata = [ordered]@{
        ToolVersion     = $ToolVersion
        StartedAt       = $startedAt
        FinishedAt      = $null
        Host            = $env:COMPUTERNAME
        User            = "$env:USERDOMAIN\$env:USERNAME"
        PSVersion       = $PSVersionTable.PSVersion.ToString()
        Domain          = $Domain
        Parameters      = @{
            Domain             = $Domain
            DomainController   = $DomainController
            Checks             = $Checks
            EventLookbackDays  = $EventLookbackDays
            IncludeEventLogs   = $IncludeEventLogs
            IncludeSecurityLog = $IncludeSecurityLog
            IncludeDnsDetails  = $IncludeDnsDetails
            IncludeDcdiag      = $IncludeDcdiag
            IncludeTopology    = $IncludeTopology
            IncludeGroupPolicy = $IncludeGroupPolicy
            SkipPing           = $SkipPing
            ThrottleLimit      = $ThrottleLimit
            NoReport           = $NoReport
            ReportFormat       = $ReportFormat
        }
        DcsDiscovered   = 0
        DcsEvaluated    = 0
        DcsUnreachable  = 0
        ModulesExecuted = @()
        ModulesSkipped  = @()
        Limitations     = @(
            'IPv6 / AAAA checks intentionally disabled.',
            'Security log collection requires both -IncludeEventLogs and -IncludeSecurityLog.'
        )
    }

    Write-ADHCLog -Level Info -Message "AD Health Check Toolkit $ToolVersion starting (assessment run)" -Logger $logger

    # ------------------------------------------------------------------
    # Discovery
    # ------------------------------------------------------------------
    Write-ADHCLog -Level Info -Message 'Starting discovery phase' -Logger $logger

    $discovery = Invoke-ADHCDiscovery `
        -Domain             $Domain `
        -DomainController   $DomainController `
        -Capabilities       $Capabilities `
        -Credential         $Credential `
        -Logger             $logger

    if (-not $discovery.Success) {
        Write-ADHCLog -Level Error -Message "Discovery failed: $($discovery.ErrorMessage)" -Logger $logger
        throw "Domain discovery failed: $($discovery.ErrorMessage)"
    }

    $runMetadata.Domain         = $discovery.Domain
    $runMetadata.DcsDiscovered  = @($discovery.DomainControllers).Count
    $runMetadata.DcsUnreachable = @($discovery.DomainControllers | Where-Object { $_.Reachable -eq $false }).Count

    Write-ADHCLog -Level Info -Message "Domain: $($discovery.Domain) | DCs: $(@($discovery.DomainControllers).Count) | Unreachable: $($runMetadata.DcsUnreachable)" -Logger $logger

    if ($OnDiscoveryDone) {
        & $OnDiscoveryDone @{
            Domain            = $discovery.Domain
            DomainControllers = $discovery.DomainControllers
            DcsDiscovered     = $runMetadata.DcsDiscovered
            DcsUnreachable    = $runMetadata.DcsUnreachable
        }
    }

    # ------------------------------------------------------------------
    # Category selection
    # ------------------------------------------------------------------
    if ($Checks -and $Checks.Count -gt 0) {
        $categoriesToRun = @($Checks)
    } else {
        $base = @($script:CheckCatalog.Categories | Where-Object { $_.EnabledByDefault } | ForEach-Object { $_.Name })

        $extra = @()
        if ($IncludeDcdiag)      { $extra += 'DCDiag' }
        if ($IncludeTopology)    { $extra += 'Topology' }
        if ($IncludeEventLogs)   { $extra += 'EventLogs' }
        if ($IncludeGroupPolicy) { $extra += 'GroupPolicy' }

        $categoriesToRun = @($base + $extra | Select-Object -Unique)
    }

    $allResults   = [System.Collections.Generic.List[object]]::new()
    $totalToRun   = $categoriesToRun.Count
    $currentIndex = 0

    # ------------------------------------------------------------------
    # Orchestration loop
    # ------------------------------------------------------------------
    foreach ($category in $categoriesToRun) {
        $currentIndex++
        $entry = $script:CheckCatalog.Categories | Where-Object { $_.Name -eq $category }

        if (-not $entry) {
            Write-ADHCLog -Level Warning -Message "Unknown category: $category" -Logger $logger
            $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Unknown category' }
            if ($OnCategoryEnd) {
                & $OnCategoryEnd @{
                    Index = $currentIndex; Total = $totalToRun; Name = $category
                    Status = 'SKIPPED'; Duration = [TimeSpan]::Zero
                    ResultCount = 0
                    PassCount = 0; InfoCount = 0; WarnCount = 0; FailCount = 0; UnknownCount = 0
                    Reason = 'Unknown category'
                }
            }
            continue
        }

        $moduleFile = Join-Path $ScriptRoot ("Modules/" + $entry.ModuleFile)
        if (-not (Test-Path -LiteralPath $moduleFile)) {
            Write-ADHCLog -Level Warning -Message "Module file missing: $moduleFile" -Logger $logger
            $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Module file not found' }
            if ($OnCategoryEnd) {
                & $OnCategoryEnd @{
                    Index = $currentIndex; Total = $totalToRun; Name = $category
                    Status = 'SKIPPED'; Duration = [TimeSpan]::Zero
                    ResultCount = 0
                    PassCount = 0; InfoCount = 0; WarnCount = 0; FailCount = 0; UnknownCount = 0
                    Reason = 'Module file not found'
                }
            }
            continue
        }

        . $moduleFile

        if (-not (Get-Command $entry.EntryFunction -ErrorAction SilentlyContinue)) {
            Write-ADHCLog -Level Warning -Message "Entry function $($entry.EntryFunction) not found in $moduleFile" -Logger $logger
            $runMetadata.ModulesSkipped += @{ Name = $category; Reason = "Entry function missing" }
            if ($OnCategoryEnd) {
                & $OnCategoryEnd @{
                    Index = $currentIndex; Total = $totalToRun; Name = $category
                    Status = 'SKIPPED'; Duration = [TimeSpan]::Zero
                    ResultCount = 0
                    PassCount = 0; InfoCount = 0; WarnCount = 0; FailCount = 0; UnknownCount = 0
                    Reason = "Entry function missing"
                }
            }
            continue
        }

        # Conditional gates
        if ($category -eq 'DCDiag'      -and -not $IncludeDcdiag)      { $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Requires -IncludeDcdiag' };      continue }
        if ($category -eq 'EventLogs'   -and -not $IncludeEventLogs)   { $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Requires -IncludeEventLogs' };   continue }
        if ($category -eq 'Topology'    -and -not $IncludeTopology)    { $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Requires -IncludeTopology' };    continue }
        if ($category -eq 'GroupPolicy' -and -not $IncludeGroupPolicy) { $runMetadata.ModulesSkipped += @{ Name = $category; Reason = 'Requires -IncludeGroupPolicy' }; continue }

        if ($OnCategoryStart) {
            & $OnCategoryStart @{
                Index = $currentIndex; Total = $totalToRun; Name = $category
            }
        }

        Write-ADHCLog -Level Info -Message "Running category: $category ($($entry.EntryFunction))" -Logger $logger
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $ctx = @{
                Domain             = $discovery.Domain
                DomainControllers  = $discovery.DomainControllers
                Forest             = $discovery.Forest
                FSMO               = $discovery.FSMO
                Sites              = $discovery.Sites
                Capabilities       = $Capabilities
                Logger             = $logger
                Credential         = $Credential
                OutputPath         = $OutputPath
                ThrottleLimit      = $ThrottleLimit
                SkipPing           = $SkipPing
                IncludeDnsDetails  = $IncludeDnsDetails
                IncludeDcdiag      = $IncludeDcdiag
                IncludeEventLogs   = $IncludeEventLogs
                IncludeSecurityLog = $IncludeSecurityLog
                EventLookbackDays  = $EventLookbackDays
            }
            $results = & $entry.EntryFunction -Context $ctx
            if ($results) { $allResults.AddRange([object[]]@($results)) }
            $runMetadata.ModulesExecuted += @{ Name = $category; Duration = $sw.Elapsed.ToString('hh\:mm\:ss\.fff') }

            if ($OnCategoryEnd) {
                $catResults   = @($results)
                $passCount    = @($catResults | Where-Object { $_.Status -eq 'PASS'    }).Count
                $infoCount    = @($catResults | Where-Object { $_.Status -eq 'INFO'    }).Count
                $warnCount    = @($catResults | Where-Object { $_.Status -eq 'WARNING' }).Count
                $failCount    = @($catResults | Where-Object { $_.Status -eq 'FAIL'    }).Count
                $unknownCount = @($catResults | Where-Object { $_.Status -eq 'UNKNOWN' }).Count

                $catStatus = 'PASS'
                if     ($failCount -gt 0)    { $catStatus = 'FAIL' }
                elseif ($warnCount -gt 0)    { $catStatus = 'WARNING' }
                elseif ($catResults.Count -eq 0) { $catStatus = 'INFO' }
                elseif ($unknownCount -gt 0 -and $passCount -eq 0) { $catStatus = 'UNKNOWN' }

                & $OnCategoryEnd @{
                    Index        = $currentIndex
                    Total        = $totalToRun
                    Name         = $category
                    Status       = $catStatus
                    Duration     = $sw.Elapsed
                    ResultCount  = $catResults.Count
                    PassCount    = $passCount
                    InfoCount    = $infoCount
                    WarnCount    = $warnCount
                    FailCount    = $failCount
                    UnknownCount = $unknownCount
                }
            }
        } catch {
            Write-ADHCLog -Level Error -Message "Category $category threw: $($_.Exception.Message)" -Logger $logger
            $allResults.Add((New-CheckResult `
                -CheckId              "SYS-$category" -Category $category -Domain $discovery.Domain `
                -Status               'UNKNOWN' -Severity 'Medium' `
                -Title                "Category $category failed to execute" `
                -Description          "The module for category $category threw an unhandled error." `
                -Evidence             @{ Error = $_.Exception.Message; StackTrace = $_.ScriptStackTrace } `
                -PotentialImpact      'Category results are incomplete.' `
                -PossibleCauses       @('Tool bug','Environment limitation','Permission issue') `
                -RecommendedInvestigation @("Review execution log at $($logger.LogFilePath)") `
                -IsInconclusive       $true -Duration $sw.Elapsed))
            $runMetadata.ModulesSkipped += @{ Name = $category; Reason = $_.Exception.Message }

            if ($OnCategoryEnd) {
                & $OnCategoryEnd @{
                    Index = $currentIndex; Total = $totalToRun; Name = $category
                    Status = 'UNKNOWN'; Duration = $sw.Elapsed
                    ResultCount = 1
                    PassCount = 0; InfoCount = 0; WarnCount = 0; FailCount = 0; UnknownCount = 1
                    Reason = $_.Exception.Message
                }
            }
        } finally {
            $sw.Stop()
        }
    }

    $runMetadata.FinishedAt = (Get-Date).ToUniversalTime()
    Write-ADHCLog -Level Info -Message "All categories completed. Total checks: $($allResults.Count)" -Logger $logger

    # ------------------------------------------------------------------
    # Recompute reachability from Connectivity results
    # ------------------------------------------------------------------
    $reachResults = $allResults | Where-Object { $_.CheckId -eq 'CONN-REACH' }
    if ($reachResults) {
        $runMetadata.DcsEvaluated   = @($reachResults | Where-Object { $_.Status -ne 'FAIL' }).Count
        $runMetadata.DcsUnreachable = @($reachResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    }

    # ------------------------------------------------------------------
    # Consolidate
    # ------------------------------------------------------------------
    $consolidated = [PSCustomObject]@{
        PSTypeName   = 'ADHC.ConsolidatedResult'
        Metadata     = [PSCustomObject]$runMetadata
        Discovery    = $discovery
        Capabilities = $Capabilities
        Results      = $allResults.ToArray()
    }

    $summary = Get-ADHCResultSummary -Results $consolidated.Results
    $score   = Get-ADHCHealthScore   -Results $consolidated.Results

    # ------------------------------------------------------------------
    # Report
    # ------------------------------------------------------------------
    $reportPaths = $null
    if (-not $NoReport) {
        $formats = $ReportFormat
        if (-not $formats -or $formats.Count -eq 0) { $formats = @('HTML','JSON','CSV') }

        try {
            $reportPaths = New-ADHCReport `
                -Consolidated $consolidated `
                -Score        $score `
                -OutputPath   $OutputPath `
                -Formats      $formats
            Write-ADHCLog -Level Info -Message "Report generated: HTML=$($reportPaths.Html) JSON=$($reportPaths.Json) CSV=$($reportPaths.Csv)" -Logger $logger

            if ($OnReportGenerated) { & $OnReportGenerated $reportPaths }
        } catch {
            Write-ADHCLog -Level Error -Message "Report generation failed: $($_.Exception.Message)" -Logger $logger
            Write-Warning "Report generation failed: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        PSTypeName   = 'ADHC.AssessmentResult'
        Consolidated = $consolidated
        Score        = $score
        Summary      = $summary
        ReportPaths  = $reportPaths
        Logger       = $logger
        OutputPath   = $OutputPath
        StartedAt    = $startedAt
        FinishedAt   = $runMetadata.FinishedAt
    }
}