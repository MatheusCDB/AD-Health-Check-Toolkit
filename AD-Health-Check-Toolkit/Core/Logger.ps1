Set-StrictMode -Version Latest
$script:ADHCDefaultLogger = $null

function Initialize-ADHCLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$ToolVersion
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath   = Join-Path $LogDirectory "ADHC-$timestamp.log"

    $logger = [PSCustomObject]@{
        PSTypeName   = 'ADHC.Logger'
        LogFilePath  = $logPath
        StartedAt    = (Get-Date).ToUniversalTime()
        ToolVersion  = $ToolVersion
        IsMuted      = $false
    }

    "[{0}] === AD Health Check Toolkit {1} ===" -f (Get-Date -Format 'u'), $ToolVersion |
        Out-File -LiteralPath $logPath -Encoding utf8 -Append

    $script:ADHCDefaultLogger = $logger
    $logger
}

function Write-ADHCLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug','Info','Warning','Error')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [psobject]$Logger
    )

    if (-not $Logger) { $Logger = $script:ADHCDefaultLogger }

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line  = "[{0}] [{1,-7}] {2}" -f $stamp, $Level, $Message

    if ($Logger -and $Logger.LogFilePath) {
        try {
            $line | Out-File -LiteralPath $Logger.LogFilePath -Encoding utf8 -Append -ErrorAction Stop
        } catch {
            Write-Warning "Logger failed to write to $($Logger.LogFilePath): $($_.Exception.Message)"
        }
    }

    switch ($Level) {
        'Debug'   { Write-Verbose $Message }
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error   $Message -ErrorAction Continue }
    }
}