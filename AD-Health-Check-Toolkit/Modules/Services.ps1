Set-StrictMode -Version Latest

function Get-ADHCServiceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string[]]$ServiceNames,
        [PSCredential]$Credential
    )

    if (Test-ADHCIsLocalhost -ComputerName $ComputerName) {
        try {
            $svcs = Get-Service -Name $ServiceNames -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Success=$true; Method='Local'; Services=$svcs; Error=$null }
        } catch {
            return [PSCustomObject]@{ Success=$false; Method='Local'; Services=@(); Error=$_.Exception.Message }
        }
    }

    # Remote via WinRM
    $winrmError = $null
    try {
        $remote = Invoke-ADHCRemote -ComputerName $ComputerName -TimeoutSeconds 30 -Credential $Credential `
            -ScriptBlock {
                param($names)
                Get-Service -Name $names -ErrorAction SilentlyContinue |
                    Select-Object Name, DisplayName, Status, StartType
            } -ArgumentList @(,$ServiceNames)
        if ($remote.Success) {
            return [PSCustomObject]@{ Success=$true; Method='WinRM'; Services=$remote.Output; Error=$null }
        }
        $winrmError = $remote.Error
    } catch { $winrmError = $_.Exception.Message }

    # Fallback CIM
    try {
        $filter = ($ServiceNames | ForEach-Object { "Name='$_'" }) -join ' OR '
        $cim = Get-CimInstance -ClassName Win32_Service -ComputerName $ComputerName -Filter $filter -ErrorAction Stop
        $svcs = $cim | ForEach-Object {
            $status = switch ($_.State) {
                'Running' { 'Running' }
                default   { 'Stopped' }
            }
            $startType = switch ($_.StartMode) {
                'Auto'     { 'Automatic' }
                'Manual'   { 'Manual'   }
                'Disabled' { 'Disabled' }
                default    { $_.StartMode }
            }
            [PSCustomObject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                Status      = $status
                StartType   = $startType
            }
        }
        return [PSCustomObject]@{ Success=$true; Method='CIM'; Services=$svcs; Error=$null }
    } catch {
        return [PSCustomObject]@{
            Success=$false; Method=$null; Services=@()
            Error="WinRM: $winrmError; CIM: $($_.Exception.Message)"
        }
    }
}

function Invoke-ADHCServices {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Context)

    $defaults = Get-ADHCDefaults
    $policy   = $defaults.Services.Policy
    $names    = @($defaults.Services.Required)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($dc in $Context.DomainControllers) {
        Write-ADHCLog -Level Info -Message "Services: evaluating $($dc.Fqdn)" -Logger $Context.Logger
        $dcSw = [System.Diagnostics.Stopwatch]::StartNew()

        $probe = Get-ADHCServiceState -ComputerName $dc.Fqdn -ServiceNames $names -Credential $Context.Credential

        if (-not $probe.Success) {
            $results.Add((New-CheckResult `
                -CheckId 'SVC-QUERY' -Category 'Services' `
                -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status 'UNKNOWN' -Severity 'Medium' `
                -Title "Could not query services on $($dc.Fqdn)" `
                -Description 'Neither WinRM nor CIM returned service state.' `
                -Evidence @{ Error = $probe.Error; AttemptedMethods = @('WinRM','CIM') } `
                -PotentialImpact 'Service state unknown for this DC; other checks may be affected.' `
                -PossibleCauses @('WinRM disabled and WMI/RPC blocked','Permissions insufficient','Host unreachable') `
                -RecommendedInvestigation @('Verify WinRM and RPC reachability; check execution account rights.') `
                -SuggestedCommands @("Test-WSMan -ComputerName $($dc.Fqdn)", "Get-CimInstance Win32_Service -ComputerName $($dc.Fqdn) -Filter \`"Name='NTDS'\`"") `
                -IsInconclusive $true -Duration $dcSw.Elapsed -ToolUsed $probe.Method
            ))
            $dcSw.Stop(); continue
        }

        $byName = @{}
        foreach ($s in $probe.Services) {
            if ($s -and $s.Name) { $byName[$s.Name.ToString().ToLowerInvariant()] = $s }
        }

        foreach ($svc in $names) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $p  = $policy[$svc]
            if (-not $p) { $p = @{ MustExist=$false; MustBeRunning=$false; Severity='Medium' } }

            if (-not $byName.ContainsKey($svc.ToLowerInvariant())) {
                $status = if ($p.MustExist) { 'FAIL' } else { 'INFO' }
                $sev    = Get-ADHCSeverity -CheckId 'SVC-MISSING' -Status $status

                if ($p.MustExist) {
                    $impactText = "$svc is required for AD DS."
                } else {
                    $impactText = "$svc missing may be expected depending on role layout."
                }

                $results.Add((New-CheckResult `
                    -CheckId ("SVC-{0}" -f $svc.ToUpperInvariant()) -Category 'Services' `
                    -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                    -Status $status -Severity $sev.Severity `
                    -Title ("Service {0} not present on {1}" -f $svc, $dc.Fqdn) `
                    -Description ("Service {0} was not found." -f $svc) `
                    -Evidence @{ Service=$svc; Found=$false; Method=$probe.Method } `
                    -PotentialImpact $impactText `
                    -PossibleCauses @('Role not installed on this DC','Service removed','Permissions filtered the result') `
                    -RecommendedInvestigation @("Verify roles installed on $($dc.Fqdn)") `
                    -SuggestedCommands @("Get-WindowsFeature *DNS*", "Get-Service -Name $svc -ComputerName $($dc.Fqdn)") `
                    -Duration $sw.Elapsed -ToolUsed $probe.Method
                ))
                $sw.Stop(); continue
            }

            $s         = $byName[$svc.ToLowerInvariant()]
            $state     = $s.Status.ToString()
            $startType = if ($s.StartType) { $s.StartType.ToString() } else { 'Unknown' }

            if ($state -ne 'Running') {
                $status = 'FAIL'
                $title  = "Service $svc is $state on $($dc.Fqdn)"
                $impact = "A stopped $svc breaks dependent AD functionality."
                $sev    = Get-ADHCSeverity -CheckId 'SVC-STOPPED' -Status $status
            } elseif ($startType -eq 'Disabled') {
                $status = 'WARNING'
                $title  = "Service $svc is running but Disabled on $($dc.Fqdn)"
                $impact = "$svc will not start on next reboot."
                $sev    = Get-ADHCSeverity -CheckId 'SVC-DISABLED' -Status $status
            } elseif ($startType -eq 'Automatic') {
                $status = 'PASS'
                $title  = "Service $svc running on $($dc.Fqdn)"
                $impact = 'No impact.'
                $sev    = [PSCustomObject]@{
                    Severity      = 'Informational'
                    Justification = "Service $svc running and set to Automatic."
                    Escalated     = $false
                }
            } else {
                $status = 'WARNING'
                $title  = "Service $svc running but StartType=$startType on $($dc.Fqdn)"
                $impact = 'Verify whether this is intentional for the role.'
                $sev    = Get-ADHCSeverity -CheckId 'SVC-DEGRADED' -Status $status
            }

            $results.Add((New-CheckResult `
                -CheckId ("SVC-{0}" -f $svc.ToUpperInvariant()) -Category 'Services' `
                -Domain $Context.Domain -DomainController $dc.Fqdn -ComputerName $dc.Fqdn `
                -Status $status -Severity $sev.Severity `
                -Title $title `
                -Description ("State: {0}; StartType: {1}; Method: {2}" -f $state, $startType, $probe.Method) `
                -Evidence @{ Service=$svc; Status=$state; StartType=$startType; Method=$probe.Method } `
                -PotentialImpact $impact `
                -PossibleCauses @('Service crashed','Manual stop','Startup dependency failed','Misconfigured') `
                -RecommendedInvestigation @("Check the System log for $svc errors","Verify dependencies for $svc are running") `
                -SuggestedCommands @("Get-Service -Name $svc -ComputerName $($dc.Fqdn) | Format-List *") `
                -Duration $sw.Elapsed -ToolUsed $probe.Method
            ))
            $sw.Stop()
        }

        $dcSw.Stop()
        Write-ADHCLog -Level Info -Message "Services: done for $($dc.Fqdn) in $($dcSw.Elapsed.TotalSeconds.ToString('F1'))s" -Logger $Context.Logger
    }

    $results.ToArray()
}