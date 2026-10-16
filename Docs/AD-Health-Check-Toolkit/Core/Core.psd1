@{
    RootModule        = 'Core.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7a1e4c9-3d2f-4f8a-9c11-6a2f7e3b8d55'
    Author            = 'AD Health Check Toolkit'
    CompanyName       = 'Community'
    Copyright         = '(c) AD Health Check Toolkit contributors'
    Description       = 'Core primitives for AD Health Check Toolkit: result model, logging, capability probing, remoting, severity.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'New-CheckResult',
        'New-CheckContext',
        'Initialize-ADHCLog',
        'Write-ADHCLog',
        'Get-ADHCCapabilities',
        'Test-ADHCCommandExists',
        'Test-ADHCIsLocalhost',
        'Invoke-ADHCRemote',
        'New-ADHCSession',
        'Remove-ADHCSession',
        'Set-ADHCSeverityRules',
        'Set-ADHCDefaults',
        'Get-ADHCDefaults',
        'Get-ADHCSeverity',
        'Get-ADHCResultSummary',
        'ConvertTo-ADHCHtmlSafe'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}