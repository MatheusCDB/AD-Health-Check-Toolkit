Set-StrictMode -Version Latest

# =============================================================================
#  UI.Summary.ps1
#  Executive summary after an assessment finishes.
#  Takes real numbers from the consolidated result and the score.
# =============================================================================

function Show-ADHCExecutiveSummary {
    <#
    .SYNOPSIS
        Renders the post-run summary panel.
        Returns nothing; the caller controls what comes next.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Assessment
    )

    $consolidated = $Assessment.Consolidated
    $summary      = $Assessment.Summary
    $score        = $Assessment.Score
    $meta         = $consolidated.Metadata

    $ch = Get-ADHCBoxChars
    $cPrimary = Get-ADHCColor -Name 'Primary'
    $cMuted   = Get-ADHCColor -Name 'Muted'

    # Overall status from the score band.
    $overall = 'SAUDAVEL'
    switch ($score.BandLabel) {
        'Healthy'   { $overall = 'SAUDAVEL' }
        'Good'      { $overall = 'BOM' }
        'Attention' { $overall = 'ATENCAO' }
        'Degraded'  { $overall = 'DEGRADADO' }
        'Critical'  { $overall = 'CRITICO' }
    }
    $overallColorName = 'Success'
    switch ($score.BandLabel) {
        'Attention' { $overallColorName = 'Warning' }
        'Degraded'  { $overallColorName = 'Warning' }
        'Critical'  { $overallColorName = 'Danger' }
    }

    Write-Host ''
    Write-Host '  RESUMO DA AUDITORIA' -ForegroundColor $cPrimary
    Write-Host ''

    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add(('Domain Controllers avaliados : {0}' -f $meta.DcsDiscovered))
    $rows.Add(('Verificacoes aprovadas       : {0}' -f $summary.PASS))
    $rows.Add(('Alertas encontrados          : {0}' -f $summary.WARNING))
    $rows.Add(('Falhas identificadas         : {0}' -f $summary.FAIL))
    $rows.Add(('Verificacoes inconclusivas   : {0}' -f ($summary.UNKNOWN + $summary.Inconclusive)))
    $rows.Add(('Informacoes                  : {0}' -f $summary.INFO))
    $rows.Add(('Total de verificacoes        : {0}' -f $summary.Total))

    Write-ADHCBox -Lines $rows -Title 'Resultado' -Color 'Primary'

    Write-Host ''
    Write-Host ('  Pontuacao : {0}/100' -f $score.Score) -ForegroundColor $cPrimary
    Write-Host ('  Status    : {0}' -f $overall) -ForegroundColor (Get-ADHCColor -Name $overallColorName)

    # Show non-pass, non-info rows (highest severity first)
    $attention = @($consolidated.Results | Where-Object { $_.Status -ne 'PASS' -and $_.Status -ne 'INFO' })
    if ($attention.Count -gt 0) {
        Write-Host ''
        Write-Host '  Itens que requerem atencao:' -ForegroundColor (Get-ADHCColor -Name 'Warning')
        Write-Host ''

        $sorted = $attention | Sort-Object -Property @{Expression={
            switch ($_.Severity) {
                'Critical' { 0 }
                'High'     { 1 }
                'Medium'   { 2 }
                'Low'      { 3 }
                default    { 4 }
            }
        }}
        foreach ($r in $sorted) {
            $tag = '[{0,-7}]' -f $r.Status
            $statusCol = Get-ADHCColor -Name (Get-ADHCStatusColor -Status $r.Status)
            Write-Host '    ' -NoNewline
            Write-Host $tag -ForegroundColor $statusCol -NoNewline
            Write-Host (' {0}' -f $r.CheckId) -ForegroundColor $cPrimary -NoNewline
            Write-Host ('  {0}' -f $r.Title) -ForegroundColor $cMuted
        }
    }

    Write-Host ''
    Write-Host ('  Relatorios gerados em: {0}' -f $Assessment.OutputPath) -ForegroundColor $cMuted
    Write-Host ''
}

function Get-ADHCSummaryStatusLabel {
    <#
    .SYNOPSIS
        Returns a short label used by the main menu status line.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Assessment)
    switch ($Assessment.Score.BandLabel) {
        'Healthy'   { return 'SAUDAVEL' }
        'Good'      { return 'BOM' }
        'Attention' { return 'ATENCAO' }
        'Degraded'  { return 'DEGRADADO' }
        'Critical'  { return 'CRITICO' }
        default     { return 'DESCONHECIDO' }
    }
}