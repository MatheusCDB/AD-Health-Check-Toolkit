Set-StrictMode -Version Latest

function Get-ADHCHealthScore {
    <#
    .SYNOPSIS
        Computes an explainable health score from a set of CheckResult objects.

    .DESCRIPTION
        Score = BaseScore - sum(weight(severity) for each failing/unknown check).
        PASS and INFO never deduct. UNKNOWN deducts weight * UnknownWeightFactor.
        Result is clamped to [0, BaseScore].

        Returns a rich object that lists which checks deducted the most, so the
        score is auditable from the report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results
    )

    $defaults = Get-ADHCDefaults
    $cfg      = $defaults.Reporting.Scoring

    $base        = [int]$cfg.BaseScore
    $weights     = $cfg.Weights
    $unknownFac  = [double]$cfg.UnknownWeightFactor
    $bands       = $cfg.Bands

    $deductions = [System.Collections.Generic.List[object]]::new()
    $totalDeduction = 0.0

    foreach ($r in @($Results)) {
        if ($null -eq $r) { continue }

        $weight = 0
        if ($weights.ContainsKey($r.Severity)) { $weight = [int]$weights[$r.Severity] }

        $applies = $false
        $factor  = 1.0

        switch ($r.Status) {
            'PASS'    { $applies = $false }
            'INFO'    { $applies = $false }
            'WARNING' { $applies = $true  }
            'FAIL'    { $applies = $true  }
            'UNKNOWN' { $applies = $true; $factor = $unknownFac }
        }

        if (-not $applies) { continue }
        if ($weight -le 0) { continue }

        $value = $weight * $factor
        $totalDeduction += $value

        $deductions.Add([PSCustomObject]@{
            CheckId            = $r.CheckId
            Category           = $r.Category
            DomainController   = $r.DomainController
            Status             = $r.Status
            Severity           = $r.Severity
            Weight             = $weight
            Factor             = $factor
            Applied            = $value
            Title              = $r.Title
        })
    }

    $score = $base - $totalDeduction
    if ($score -lt 0)   { $score = 0 }
    if ($score -gt $base) { $score = $base }
    $score = [math]::Round($score, 1)

    $band = $bands | Where-Object { $score -ge $_.Min -and $score -le $_.Max } | Select-Object -First 1
    if (-not $band) { $band = $bands[-1] }

    # Top deductors (audit trail), highest contribution first, capped at 10.
    $top = @($deductions | Sort-Object -Property Applied -Descending | Select-Object -First 10)

    [PSCustomObject]@{
        PSTypeName        = 'ADHC.HealthScore'
        Score             = $score
        BaseScore         = $base
        TotalDeduction    = [math]::Round($totalDeduction, 1)
        BandLabel         = $band.Label
        BandColor         = $band.Color
        TopDeductions     = $top
        AllDeductions     = $deductions.ToArray()
        Weights           = $weights
        UnknownWeightFactor = $unknownFac
    }
}