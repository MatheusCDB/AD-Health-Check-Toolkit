Set-StrictMode -Version Latest

$script:ADHCSessions = @{}

function Test-ADHCIsLocalhost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)

    $shortNames = @($env:COMPUTERNAME.ToLowerInvariant())
    if ($env:USERDNSDOMAIN) {
        $shortNames += "$($env:COMPUTERNAME).$($env:USERDNSDOMAIN)".ToLowerInvariant()
    }
    $shortNames += 'localhost', '127.0.0.1', '.'

    if ($shortNames -contains $ComputerName.ToLowerInvariant()) { return $true }

    try {
        $targetIps = [System.Net.Dns]::GetHostAddresses($ComputerName) |
                     ForEach-Object { $_.IPAddressToString }
        $localIps  = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                     ForEach-Object { $_.IPAddressToString }
        foreach ($ip in $targetIps) { if ($localIps -contains $ip) { return $true } }
    } catch { }
    return $false
}

function New-ADHCSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [PSCredential]$Credential,
        [int]$OpenTimeoutSeconds = 15
    )

    if ($script:ADHCSessions.ContainsKey($ComputerName)) {
        return $script:ADHCSessions[$ComputerName]
    }

    $opts = @{
        OpenTimeout          = [TimeSpan]::FromSeconds($OpenTimeoutSeconds)
        OperationTimeout     = [TimeSpan]::FromSeconds(60)
        CancelTimeout        = [TimeSpan]::FromSeconds(5)
        IdleTimeout          = [TimeSpan]::FromMinutes(10)
        SkipCACheck          = $false
        SkipCNCheck          = $false
    }

    $params = @{
        ComputerName  = $ComputerName
        SessionOption = (New-PSSessionOption @opts)
        ErrorAction   = 'Stop'
    }
    if ($Credential) { $params.Credential = $Credential }

    $session = New-PSSession @params
    $script:ADHCSessions[$ComputerName] = $session
    $session
}

function Remove-ADHCSession {
    [CmdletBinding()]
    param([string]$ComputerName)

    if ($ComputerName) {
        if ($script:ADHCSessions.ContainsKey($ComputerName)) {
            Remove-PSSession -Session $script:ADHCSessions[$ComputerName] -ErrorAction SilentlyContinue
            $script:ADHCSessions.Remove($ComputerName)
        }
    } else {
        foreach ($k in @($script:ADHCSessions.Keys)) {
            Remove-PSSession -Session $script:ADHCSessions[$k] -ErrorAction SilentlyContinue
        }
        $script:ADHCSessions.Clear()
    }
}

function Invoke-ADHCRemote {
    <#
    .SYNOPSIS
        Executes a scriptblock locally or remotely, with timeout and structured error handling.
    .OUTPUTS
        ADHC.RemoteResult with Success, Output, Error, Duration, ExecutedLocally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 60,
        [PSCredential]$Credential,
        [switch]$UseCimFallback
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $isLocal = Test-ADHCIsLocalhost -ComputerName $ComputerName

    if ($isLocal) {
        try {
            $out = & $ScriptBlock @ArgumentList
            return [PSCustomObject]@{
                PSTypeName        = 'ADHC.RemoteResult'
                Success           = $true
                Output            = $out
                Error             = $null
                Duration          = $sw.Elapsed
                ExecutedLocally   = $true
                ComputerName      = $ComputerName
            }
        } catch {
            return [PSCustomObject]@{
                PSTypeName        = 'ADHC.RemoteResult'
                Success           = $false
                Output            = $null
                Error             = $_.Exception.Message
                Duration          = $sw.Elapsed
                ExecutedLocally   = $true
                ComputerName      = $ComputerName
            }
        } finally { $sw.Stop() }
    }

    # Remote path
    try {
        $session = New-ADHCSession -ComputerName $ComputerName -Credential $Credential
        $invokeParams = @{
            Session         = $session
            ScriptBlock     = $ScriptBlock
            ArgumentList    = $ArgumentList
            ErrorAction     = 'Stop'
            ErrorVariable   = 'icmErr'
        }
        $out = Invoke-Command @invokeParams
        return [PSCustomObject]@{
            PSTypeName        = 'ADHC.RemoteResult'
            Success           = $true
            Output            = $out
            Error             = $null
            Duration          = $sw.Elapsed
            ExecutedLocally   = $false
            ComputerName      = $ComputerName
        }
    } catch {
        Remove-ADHCSession -ComputerName $ComputerName -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            PSTypeName        = 'ADHC.RemoteResult'
            Success           = $false
            Output            = $null
            Error             = $_.Exception.Message
            Duration          = $sw.Elapsed
            ExecutedLocally   = $false
            ComputerName      = $ComputerName
        }
    } finally { $sw.Stop() }
}