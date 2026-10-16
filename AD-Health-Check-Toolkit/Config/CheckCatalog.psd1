@{
    Categories = @(
        @{ Name='Connectivity';        ModuleFile='Connectivity.ps1';        EntryFunction='Invoke-ADHCConnectivity';        EnabledByDefault=$true;  Description='ICMP, TCP ports, DNS resolution, admin access.';       RequiresElevation=$false }
        @{ Name='Services';            ModuleFile='Services.ps1';            EntryFunction='Invoke-ADHCServices';            EnabledByDefault=$true;  Description='Essential Windows/AD DS services per DC.';                 RequiresElevation=$false }
        @{ Name='Replication';         ModuleFile='Replication.ps1';         EntryFunction='Invoke-ADHCReplication';         EnabledByDefault=$true;  Description='AD replication health (AD cmdlets + repadmin).';          RequiresElevation=$false }
        @{ Name='Topology';            ModuleFile='Topology.ps1';            EntryFunction='Invoke-ADHCTopology';            EnabledByDefault=$false; Description='Sites, subnets, connection objects, bridgeheads.';       RequiresElevation=$false }
        @{ Name='DNS';                 ModuleFile='DNS.ps1';                 EntryFunction='Invoke-ADHCDns';                 EnabledByDefault=$true;  Description='DNS dependency checks (SRV, A, reverse).';                RequiresElevation=$false }
        @{ Name='SysvolNetlogon';      ModuleFile='SysvolNetlogon.ps1';      EntryFunction='Invoke-ADHCSysvolNetlogon';      EnabledByDefault=$true;  Description='SYSVOL/NETLOGON shares and DFSR health.';                 RequiresElevation=$false }
        @{ Name='FSMO';                ModuleFile='FSMO.ps1';                EntryFunction='Invoke-ADHCFsmo';                EnabledByDefault=$true;  Description='FSMO role holders and reachability.';                    RequiresElevation=$false }
        @{ Name='TimeSynchronization'; ModuleFile='TimeSynchronization.ps1'; EntryFunction='Invoke-ADHCTimeSynchronization'; EnabledByDefault=$true;  Description='w32tm status and time source validation.';                RequiresElevation=$false }
        @{ Name='DCDiag';              ModuleFile='DCDiag.ps1';              EntryFunction='Invoke-ADHCDcdiag';              EnabledByDefault=$true;  Description='Selected dcdiag tests, per DC.';                          RequiresElevation=$false }
        @{ Name='EventLogs';           ModuleFile='EventLogs.ps1';           EntryFunction='Invoke-ADHCEventLogs';           EnabledByDefault=$false; Description='Significant Windows events.';                            RequiresElevation=$false }
        @{ Name='GroupPolicy';         ModuleFile='GroupPolicy.ps1';         EntryFunction='Invoke-ADHCGroupPolicy';         EnabledByDefault=$false; Description='GPO infrastructure checks (non-destructive).';           RequiresElevation=$false }
    )
}