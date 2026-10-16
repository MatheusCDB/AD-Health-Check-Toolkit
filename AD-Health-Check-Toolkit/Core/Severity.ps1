Set-StrictMode -Version Latest

$script:ADHCSeverityRules = $null

function Set-ADHCSeverityRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Rules)
    $script:ADHCSeverityRules = $Rules
}

function Get-ADHCSeverity {
    <#
    .SYNOPSIS
        Returns the severity (and optional escalation) for a given CheckId
        based on versioned rules in Config/SeverityRules.psd1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)]
        [ValidateSet('PASS','WARNING','FAIL','INFO','UNKNOWN')]
        [string]$Status,
        [hashtable]$Evidence = @{}
    )

    if (-not $script:ADHCSeverityRules) {
        return [PSCustomObject]@{
            Severity      = 'Medium'
            Justification = 'Severity rules not loaded; defaulting to Medium.'
            Escalated     = $false
        }
    }

    $rule = $script:ADHCSeverityRules[$CheckId]
    if (-not $rule) {
        # Fallback by status
        $fallback = switch ($Status) {
            'PASS'    { 'Informational' }
            'INFO'    { 'Informational' }
            'WARNING' { 'Medium' }
            'FAIL'    { 'High' }
            'UNKNOWN' { 'Low' }
        }
        return [PSCustomObject]@{
            Severity      = $fallback
            Justification = "No specific rule for $CheckId; derived from Status=$Status."
            Escalated     = $false
        }
    }

    $severity = $rule.Default
    $escalated = $false
    $justification = $rule.Justification

    if ($rule.ContainsKey('EscalateWhen') -and $rule.ContainsKey('EscalateTo')) {
        try {
            $condition = [scriptblock]::Create($rule.EscalateWhen)
            $hit = & $condition $Evidence
            if ($hit) {
                $severity  = $rule.EscalateTo
                $escalated = $true
                $justification += " [Escalated: $($rule.EscalateWhen)]"
            }
        } catch {
            $justification += " [Escalation rule could not be evaluated: $($_.Exception.Message)]"
        }
    }

    [PSCustomObject]@{
        Severity      = $severity
        Justification = $justification
        Escalated     = $escalated
    }
}

function Get-ADHCResultSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $summary = [ordered]@{
        Total     = @($Results).Count
        PASS      = 0
        WARNING   = 0
        FAIL      = 0
        INFO      = 0
        UNKNOWN   = 0
        Critical  = 0
        High      = 0
        Medium    = 0
        Low       = 0
        Informational = 0
        Inconclusive = 0
        Skipped   = 0
    }

    foreach ($r in @($Results)) {
        if ($null -eq $r) { continue }
        if ($summary.Contains($r.Status))   { $summary[$r.Status]++ }
        if ($summary.Contains($r.Severity)) { $summary[$r.Severity]++ }
        if ($r.IsInconclusive) { $summary.Inconclusive++ }
        if ($r.WasSkipped)     { $summary.Skipped++ }
    }
    [PSCustomObject]$summary
}