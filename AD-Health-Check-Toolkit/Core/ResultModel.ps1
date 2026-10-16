Set-StrictMode -Version Latest

$script:ADHCDefaults = $null

function Set-ADHCDefaults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Defaults)
    $script:ADHCDefaults = $Defaults
}

function Get-ADHCDefaults {
    [CmdletBinding()]
    param()
    if (-not $script:ADHCDefaults) {
        throw 'Defaults not loaded. Call Set-ADHCDefaults first.'
    }
    $script:ADHCDefaults
}

function New-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$Category,
        [string]$Domain,
        [string]$DomainController,
        [string]$ComputerName,
        [Parameter(Mandatory)]
        [ValidateSet('PASS','WARNING','FAIL','INFO','UNKNOWN')]
        [string]$Status,
        [Parameter(Mandatory)]
        [ValidateSet('Critical','High','Medium','Low','Informational')]
        [string]$Severity,
        [Parameter(Mandatory)][string]$Title,
        [string]$Description,
        [hashtable]$Evidence = @{},
        [string]$PotentialImpact,
        [string[]]$PossibleCauses = @(),
        [string[]]$RecommendedInvestigation = @(),
        [string[]]$SuggestedCommands = @(),
        [string]$ErrorCode,
        [bool]$IsInconclusive = $false,
        [bool]$RequiresElevation = $false,
        [bool]$WasSkipped = $false,
        [string]$SkipReason,
        [string]$ToolUsed,
        [TimeSpan]$Duration = [TimeSpan]::Zero,
        [string]$ModuleVersion = '0.1.0'
    )

    if ($WasSkipped -and $Status -ne 'UNKNOWN') {
        Write-Warning "Check $CheckId marked as skipped but Status=$Status. Forcing Status=UNKNOWN."
        $Status = 'UNKNOWN'
        $IsInconclusive = $true
    }

    # PASS never carries a failure severity. Force Informational so HTML cards and
    # aggregated scores don't mix 'PASS' with 'Critical'/'High'.
    if ($Status -eq 'PASS') {
        $Severity = 'Informational'
    }

    [PSCustomObject]@{
        PSTypeName                 = 'ADHC.CheckResult'
        CheckId                    = $CheckId
        Category                   = $Category
        Domain                     = $Domain
        DomainController           = $DomainController
        ComputerName               = $ComputerName
        Status                     = $Status
        Severity                   = $Severity
        Title                      = $Title
        Description                = $Description
        Evidence                   = $Evidence
        PotentialImpact            = $PotentialImpact
        PossibleCauses             = $PossibleCauses
        RecommendedInvestigation   = $RecommendedInvestigation
        SuggestedCommands          = $SuggestedCommands
        DetectedAt                 = (Get-Date).ToUniversalTime()
        Duration                   = $Duration
        ErrorCode                  = $ErrorCode
        IsInconclusive             = $IsInconclusive
        RequiresElevation          = $RequiresElevation
        WasSkipped                 = $WasSkipped
        SkipReason                 = $SkipReason
        ModuleVersion              = $ModuleVersion
        ToolUsed                   = $ToolUsed
    }
}

function New-CheckContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Discovery,
        [Parameter(Mandatory)][psobject]$Capabilities,
        [Parameter(Mandatory)][psobject]$Parameters,
        [Parameter(Mandatory)][psobject]$Logger,
        [string]$OutputPath
    )
    [PSCustomObject]@{
        Domain             = $Discovery.Domain
        DomainControllers  = $Discovery.DomainControllers
        Forest             = $Discovery.Forest
        FSMO               = $Discovery.FSMO
        Sites              = $Discovery.Sites
        Capabilities       = $Capabilities
        Parameters         = $Parameters
        Logger             = $Logger
        OutputPath         = $OutputPath
    }
}

function ConvertTo-ADHCHtmlSafe {
    [CmdletBinding()]
    param([AllowNull()][string]$InputObject)
    if ($null -eq $InputObject) { return '' }
    [System.Net.WebUtility]::HtmlEncode([string]$InputObject)
}