Set-StrictMode -Version Latest

# =============================================================================
#  UI.ExportMenu.ps1
#  Export selector after an assessment. Uses the existing New-ADHCReport
#  function from Modules/ReportGenerator.ps1.
# =============================================================================

function Show-ADHCExportMenuScreen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Assessment,
        [string]$StatusMessage
    )

    $cPrimary = Get-ADHCColor -Name 'Primary'
    $cSuccess = Get-ADHCColor -Name 'Success'
    $cMuted   = Get-ADHCColor -Name 'Muted'

    Write-Host ''
    Write-Host '  EXPORTAR RELATORIOS' -ForegroundColor $cPrimary
    Write-Host ''
    Write-Host '  [1] HTML           (relatorio interativo)' -ForegroundColor $cMuted
    Write-Host '  [2] JSON           (dados estruturados)' -ForegroundColor $cMuted
    Write-Host '  [3] CSV            (planilha)' -ForegroundColor $cMuted
    Write-Host '  [4] Gerar todos' -ForegroundColor $cMuted
    Write-Host '  [0] Voltar' -ForegroundColor $cSuccess
    Write-Host ''

    if ($StatusMessage) {
        Write-Host ('  {0}' -f $StatusMessage) -ForegroundColor $cSuccess
        Write-Host ''
    }

    Write-Host ('  Diretorio: {0}' -f $Assessment.OutputPath) -ForegroundColor $cMuted
    Write-Host ''
    Write-Host '  Opcao: ' -ForegroundColor $cPrimary -NoNewline
}

function Invoke-ADHCExportMenu {
    <#
    .SYNOPSIS
        Export loop. Returns when user chooses [0].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Assessment
    )

    $statusMessage = $null

    while ($true) {
        Show-ADHCExportMenuScreen -Assessment $Assessment -StatusMessage $statusMessage

        $rawLine = [Console]::ReadLine()
        if ($null -eq $rawLine) { $rawLine = '' }
        $line = $rawLine.Trim()

        $statusMessage = $null

        switch ($line) {
            '1' {
                $statusMessage = Export-ADHCAssessment -Assessment $Assessment -Formats @('HTML')
                continue
            }
            '2' {
                $statusMessage = Export-ADHCAssessment -Assessment $Assessment -Formats @('JSON')
                continue
            }
            '3' {
                $statusMessage = Export-ADHCAssessment -Assessment $Assessment -Formats @('CSV')
                continue
            }
            '4' {
                $statusMessage = Export-ADHCAssessment -Assessment $Assessment -Formats @('HTML','JSON','CSV')
                continue
            }
            '0' {
                return
            }
            default {
                $statusMessage = "Opcao invalida: '$line'"
                continue
            }
        }
    }
}

function Export-ADHCAssessment {
    <#
    .SYNOPSIS
        Regenerates reports from the given assessment using the existing
        New-ADHCReport. Returns a short status message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Assessment,
        [Parameter(Mandatory)][string[]]$Formats
    )

    try {
        $paths = New-ADHCReport `
            -Consolidated $Assessment.Consolidated `
            -Score        $Assessment.Score `
            -OutputPath   $Assessment.OutputPath `
            -Formats      $Formats

        $parts = @()
        if ($paths.Html) { $parts += ('HTML: {0}' -f $paths.Html) }
        if ($paths.Json) { $parts += ('JSON: {0}' -f $paths.Json) }
        if ($paths.Csv)  { $parts += ('CSV:  {0}' -f $paths.Csv)  }
        return ("Relatorio(s) gerado(s). " + ($parts -join ' | '))
    } catch {
        return ('Falha ao gerar relatorio: {0}' -f $_.Exception.Message)
    }
}