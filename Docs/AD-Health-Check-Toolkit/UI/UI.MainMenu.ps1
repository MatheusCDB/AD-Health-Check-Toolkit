Set-StrictMode -Version Latest

# =============================================================================
#  UI.MainMenu.ps1
#  Main menu loop for the interactive TUI.
#  Depends on UI.Console.ps1 and UI.Banner.ps1.
# =============================================================================

#region --- Menu definition ---

function Get-ADHCMainMenu {
    <#
    .SYNOPSIS
        Returns the main menu options. Kept as a function so the options
        can be filtered by availability (e.g., hide "Another DC" when no
        other DCs are available).
    #>
    [CmdletBinding()]
    param(
        [int]$DcCount = 0,
        [switch]$DiscoveryDone
    )

    $items = [System.Collections.Generic.List[object]]::new()

    $items.Add([PSCustomObject]@{
        Key         = '1'
        Label       = 'Auditoria completa do Active Directory'
        Action      = 'FullAudit'
        Description = 'Executa todas as categorias habilitadas por padrao.'
    })
    $items.Add([PSCustomObject]@{
        Key         = '2'
        Label       = 'Selecionar auditorias'
        Action      = 'SelectChecks'
        Description = 'Escolhe categorias especificas para executar.'
    })
    $items.Add([PSCustomObject]@{
        Key         = '3'
        Label       = 'Auditoria profunda (inclui DCDiag, Topology, EventLogs, GPO)'
        Action      = 'DeepAudit'
        Description = 'Executa todas as categorias, incluindo as opt-in.'
    })
    if ($DcCount -gt 1) {
        $items.Add([PSCustomObject]@{
            Key         = '4'
            Label       = 'Auditoria de um Domain Controller especifico'
            Action      = 'SingleDc'
            Description = "Escolhe um dos $DcCount DCs para avaliar."
        })
    }
    $items.Add([PSCustomObject]@{
        Key         = '5'
        Label       = 'Verificar dependencias e pre-requisitos'
        Action      = 'ShowPrereqs'
        Description = 'Lista o estado atual das ferramentas necessarias.'
    })
    $items.Add([PSCustomObject]@{
        Key         = '0'
        Label       = 'Sair'
        Action      = 'Exit'
        Description = $null
    })

    ,$items.ToArray()
}

#endregion

#region --- Rendering ---

function Show-ADHCMainMenuScreen {
    <#
    .SYNOPSIS
        Renders the main menu screen. Returns the key chosen (as string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [string]$Domain,
        [int]$DcCount = 0,
        [string]$StatusText = 'Pronto para executar'
    )

    Show-ADHCHeader -ToolVersion $ToolVersion -Capabilities $Capabilities -Domain $Domain -DcCount $DcCount

    # Menu options
    $items = Get-ADHCMainMenu -DcCount $DcCount

    $menuLines = [System.Collections.Generic.List[string]]::new()
    foreach ($it in $items) {
        $menuLines.Add(('[{0}] {1}' -f $it.Key, $it.Label))
    }
    $menuLines.Add('')
    $menuLines.Add('Digite a opcao desejada e pressione Enter.')

    Write-ADHCBox -Lines $menuLines -Title 'AD HEALTH CHECK TOOLKIT' -Color 'Primary'
    Write-Host ''
    Write-Host ("  Status: {0}" -f $StatusText) -ForegroundColor (Get-ADHCColor -Name 'Muted')
    Write-Host ''

    $key = Read-ADHCKey -AllowEsc
    return $key
}

#endregion

#region --- Main loop ---

function Invoke-ADHCMainMenu {
    <#
    .SYNOPSIS
        Main interactive loop. Returns a hashtable with the chosen action
        and any parameters it needs:

            @{ Action = 'FullAudit' }
            @{ Action = 'SelectChecks' }
            @{ Action = 'DeepAudit' }
            @{ Action = 'SingleDc' }
            @{ Action = 'ShowPrereqs' }
            @{ Action = 'Exit' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolVersion,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [string]$Domain,
        [int]$DcCount = 0,
        [string]$StatusText = 'Pronto para executar'
    )

    while ($true) {
        $key = Show-ADHCMainMenuScreen `
            -ToolVersion  $ToolVersion `
            -Capabilities $Capabilities `
            -Domain       $Domain `
            -DcCount      $DcCount `
            -StatusText   $StatusText

        if ($null -eq $key) {
            # Escape pressed
            return @{ Action = 'Exit' }
        }

        switch ($key) {
            '1' { return @{ Action = 'FullAudit' } }
            '2' { return @{ Action = 'SelectChecks' } }
            '3' { return @{ Action = 'DeepAudit' } }
            '4' {
                if ($DcCount -gt 1) { return @{ Action = 'SingleDc' } }
                # Not applicable; redraw and continue.
                continue
            }
            '5' { return @{ Action = 'ShowPrereqs' } }
            '0' { return @{ Action = 'Exit' } }
            default {
                # Unknown key: brief message then redraw.
                Write-Host ''
                Write-Host ("  Opcao invalida: '{0}'" -f $key) -ForegroundColor (Get-ADHCColor -Name 'Warning')
                Start-Sleep -Milliseconds 700
                continue
            }
        }
    }
}

#endregion