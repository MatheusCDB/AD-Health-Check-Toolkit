@{
    'SYS-Discovery' = @{ Default = 'Critical'; Justification = 'Discovery failure prevents the entire assessment.' }

    'CONN-REACH'    = @{ Default = 'Critical';      Justification = 'An unreachable DC cannot be evaluated.' }
    'CONN-DNS-FWD'  = @{ Default = 'Critical';      Justification = 'FQDN resolution failure breaks Kerberos, LDAP, replication and GPO.' }
    'CONN-DNS-REV'  = @{ Default = 'Informational'; Justification = 'Reverse DNS is often absent and rarely breaks AD by itself.' }
    'CONN-ICMP'     = @{ Default = 'Informational'; Justification = 'ICMP may be blocked by policy; not a definitive failure.' }
    'CONN-TCP'      = @{ Default = 'High';          Justification = 'A required AD port closed may indicate a service, firewall or RPC issue.' }
    'CONN-ADMIN'    = @{ Default = 'Medium';        Justification = 'Missing admin access limits deeper remote checks.' }

    'SVC-QUERY'     = @{ Default = 'Medium';   Justification = 'Unable to determine service state.' }
    'SVC-MISSING'   = @{ Default = 'High';     Justification = 'A required service is missing.' }
    'SVC-STOPPED'   = @{ Default = 'Critical'; Justification = 'A required service is stopped.' }
    'SVC-DISABLED'  = @{ Default = 'High';     Justification = 'A required service is disabled.' }
    'SVC-DEGRADED'  = @{ Default = 'High';     Justification = 'Automatic start but not running.' }

    'DNS-ZONE-EXISTS'      = @{ Default = 'High';          Justification = 'Without the AD zone, the DC cannot resolve domain records.' }
    'DNS-ZONE-AD'          = @{ Default = 'High';          Justification = 'A non-AD-integrated zone does not replicate via AD.' }
    'DNS-ZONE-SOA'         = @{ Default = 'Medium';        Justification = 'Unexpected SOA primary can cause updates to land wrong.' }
    'DNS-NS'               = @{ Default = 'Medium';        Justification = 'NS records pointing to non-DC hosts cause failures.' }
    'DNS-SRV-LDAP'         = @{ Default = 'High';          Justification = 'Missing _ldap._tcp SRV prevents DC locator.' }
    'DNS-SRV-KERB'         = @{ Default = 'Critical';      Justification = 'Missing _kerberos._tcp SRV breaks authentication.' }
    'DNS-SRV-PDC'          = @{ Default = 'High';          Justification = 'Missing PDC SRV affects time sync and legacy lookups.' }
    'DNS-SRV-GC'           = @{ Default = 'Medium';        Justification = 'Missing GC SRV affects forest-wide lookups.' }
    'DNS-STALE-A'          = @{ Default = 'Medium';        Justification = 'A records pointing to unreachable IPs.' }
    'DNS-MULTI-A'          = @{ Default = 'Informational'; Justification = 'Multiple A records are normal in multi-NIC DCs.' }
    'DNS-REVERSE-MISSING'  = @{ Default = 'Informational'; Justification = 'Missing PTR rarely breaks AD.' }
    'DNS-DCDIAG'           = @{ Default = 'High';          Justification = 'dcdiag /test:dns aggregate verdict.' }
    'DNS-DCDIAG-PARSE'     = @{ Default = 'Informational'; Justification = 'Reports if dcdiag output was interpreted.' }
    'DNS-ZONE-QUERY'       = @{ Default = 'Medium';        Justification = 'Unable to enumerate zones.' }

    'REPL-CMDLET-AVAILABLE' = @{ Default = 'Medium';        Justification = 'Without AD replication cmdlets, checks degrade.' }
    'REPL-FAILURE'          = @{ Default = 'High'; EscalateTo = 'Critical'; EscalateWhen = '$Evidence.FailureCount -gt 3 -or $Evidence.LastSuccessDays -gt 7'; Justification = 'Persistent replication failures risk directory divergence.' }
    'REPL-LAST-SUCCESS'     = @{ Default = 'High'; EscalateTo = 'Critical'; EscalateWhen = '$Evidence.HoursSinceSuccess -gt 168'; Justification = 'Last successful replication is stale.' }
    'REPL-PARTNER-COUNT'    = @{ Default = 'Medium';        Justification = 'Fewer partners than expected DCs.' }
    'REPL-SITE-LINK'        = @{ Default = 'Medium';        Justification = 'Misconfigured or disabled site links.' }
    'REPL-REPADMIN-SUMMARY' = @{ Default = 'High';          Justification = 'repadmin /replsummary aggregate verdict.' }
    'REPL-REPADMIN-PARSE'   = @{ Default = 'Informational'; Justification = 'Reports if repadmin output was interpreted.' }

    'FSMO-DOMAIN-ROLES'       = @{ Default = 'High';   Justification = 'Domain FSMO roles must be on a reachable DC.' }
    'FSMO-FOREST-ROLES'       = @{ Default = 'High';   Justification = 'Forest FSMO roles must be on a reachable DC.' }
    'FSMO-INFRASTRUCTURE-GC'  = @{ Default = 'Medium'; Justification = 'IM should not be GC unless all DCs are GCs.' }

    'SYSVOL-SHARE-LOCAL'     = @{ Default = 'High';          Justification = 'Missing SYSVOL/NETLOGON share breaks GPO processing.' }
    'SYSVOL-PATH-DOMAIN'     = @{ Default = 'High';          Justification = 'Missing \\DC\SYSVOL\<domain> path breaks GPO access.' }
    'SYSVOL-PATH-POLICIES'   = @{ Default = 'High';          Justification = 'Missing Policies subfolder prevents GPO application.' }
    'SYSVOL-DFSR-STATE'      = @{ Default = 'High';          Justification = 'SYSVOL must use DFSR on modern Windows Server.' }
    'SYSVOL-DFSR-BACKLOG'    = @{ Default = 'Medium';        Justification = 'Backlog delays GPO updates across DCs.' }
    'NETLOGON-SHARE-CONTENT' = @{ Default = 'Informational'; Justification = 'Empty NETLOGON is valid on modern domains.' }
    'SYSVOL-QUERY'           = @{ Default = 'Medium';        Justification = 'Unable to enumerate shares.' }

    'TIME-W32TIME-SERVICE'   = @{ Default = 'High';          Justification = 'W32Time stopped or disabled breaks Kerberos (5-minute skew limit).' }
    'TIME-CONFIG-TYPE'       = @{ Default = 'High';          Justification = 'Wrong Type causes either orphan time or unexpected external dependency.' }
    'TIME-SOURCE'            = @{ Default = 'Critical';      Justification = 'A DC synchronized to Local CMOS Clock loses time and breaks Kerberos.' }
    'TIME-OFFSET'            = @{ Default = 'High';          Justification = 'Offset above tolerance can fail Kerberos authentication.' }
    'TIME-LAST-SYNC'         = @{ Default = 'Medium';        Justification = 'Long gap since last successful sync suggests the time source is unreachable.' }
    'TIME-PEERS'             = @{ Default = 'Medium';        Justification = 'No active peers when peers are expected indicates a configuration or network issue.' }
    'TIME-STRATUM'           = @{ Default = 'High';          Justification = 'Stratum 16 means the local clock is unsynchronized.' }
    'TIME-PDC-EXPECTATION'   = @{ Default = 'Medium';        Justification = 'PDC should use NTP; non-PDC DCs should use NT5DS.' }
    'TIME-W32TM-PARSE'       = @{ Default = 'Informational'; Justification = 'Reports if w32tm output was interpreted.' }

    'DCDIAG-TEST'            = @{ Default = 'High';          Justification = 'dcdiag test failure indicates a real AD DS issue.' }
    'DCDIAG-PARSE'           = @{ Default = 'Informational'; Justification = 'Reports if dcdiag output was interpreted.' }
    'DCDIAG-NOT-RUNNING'     = @{ Default = 'Medium';        Justification = 'dcdiag did not produce a recognizable verdict.' }

    'EVT-QUERY'              = @{ Default = 'Medium';        Justification = 'Unable to query one or more event logs.' }
    'EVT-DIRECTORY-SERVICE'  = @{ Default = 'High';          Justification = 'Directory Service errors may indicate AD DS issues.' }
    'EVT-DNS-SERVER'         = @{ Default = 'High';          Justification = 'DNS Server errors may affect name resolution domain-wide.' }
    'EVT-DFS-REPLICATION'    = @{ Default = 'High';          Justification = 'DFSR errors may indicate SYSVOL replication problems.' }
    'EVT-SYSTEM'             = @{ Default = 'Medium';        Justification = 'System errors may indicate driver, service or network issues.' }
    'EVT-SECURITY'           = @{ Default = 'High';          Justification = 'Security events (opt-in) may indicate auth problems or attacks.' }
    'EVT-PARSE'              = @{ Default = 'Informational'; Justification = 'Reports overall event query coverage.' }
    'EVT-SECURITY-SKIPPED'   = @{ Default = 'Informational'; Justification = 'Security log collection is opt-in.' }

    'TOPO-SITES'             = @{ Default = 'Medium';        Justification = 'A domain must have at least one valid site.' }
    'TOPO-SUBNETS'           = @{ Default = 'Medium';        Justification = 'Subnet-to-site mapping helps DC Locator and replication topology.' }
    'TOPO-SUBNET-ORPHAN'     = @{ Default = 'Medium';        Justification = 'Subnets without a site association are effectively unassigned.' }
    'TOPO-DC-SITE-ASSIGNMENT'= @{ Default = 'High';          Justification = 'DCs must be associated to a valid site for replication and DC Locator.' }
    'TOPO-SITE-LINKS'        = @{ Default = 'Medium';        Justification = 'Without site links, inter-site replication does not occur.' }
    'TOPO-SITE-LINK-BRIDGES' = @{ Default = 'Low';           Justification = 'Bridgeheads matter only when site link bridges are explicitly configured.' }
    'TOPO-CONNECTIONS'       = @{ Default = 'Medium';        Justification = 'Missing KCC connection objects prevent replication in multi-DC domains.' }
    'TOPO-ISTG'              = @{ Default = 'Informational'; Justification = 'Documents the ISTG for the site (informational only).' }
    'TOPO-QUERY'             = @{ Default = 'Medium';        Justification = 'Unable to enumerate topology objects.' }
    'TOPO-PARTIAL'           = @{ Default = 'Informational'; Justification = 'Reports partial topology collection failures.' }

    # ----- Group Policy -----
    'GPO-MODULE'             = @{ Default = 'Informational'; Justification = 'Reports whether the GroupPolicy module is available.' }
    'GPO-SYSVOL-ACCESS'      = @{ Default = 'High';          Justification = 'Without access to SYSVOL\Policies, clients cannot download GPO content.' }
    'GPO-CNTFS-READY'        = @{ Default = 'Informational'; Justification = 'A non-empty Policies folder indicates at least one GPO was ever created.' }
    'GPO-COUNT-MATCH'        = @{ Default = 'Informational'; Justification = 'Informational only; mismatches may be legitimate (filtering, staging).' }
    'GPO-SYSVOL-ORPHAN'      = @{ Default = 'Medium';        Justification = 'SYSVOL folders without a matching AD object indicate stale content.' }
    'GPO-AD-ORPHAN'          = @{ Default = 'High';          Justification = 'AD GPOs without SYSVOL folders will fail to apply on clients.' }
    'GPO-DEFAULT-POLICIES'   = @{ Default = 'Medium';        Justification = 'Missing default domain policies suggest accidental deletion or rename.' }
    'GPO-DFSR-BACKLOG'       = @{ Default = 'Medium';        Justification = 'Backlog delays SYSVOL convergence across DCs.' }
    'GPO-PARSE'              = @{ Default = 'Informational'; Justification = 'Reports overall GPO check coverage.' }
}