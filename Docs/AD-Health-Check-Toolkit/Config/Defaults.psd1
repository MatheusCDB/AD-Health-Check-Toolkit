@{
    ToolVersion = '0.1.0'
    IgnoreIPv6  = $true

    Connectivity = @{
        Ports = @(
            @{ Name = 'DNS';          Port = 53;   TCP = $true;  UDP = $true  }
            @{ Name = 'Kerberos';     Port = 88;   TCP = $true;  UDP = $true  }
            @{ Name = 'LDAP';         Port = 389;  TCP = $true;  UDP = $true  }
            @{ Name = 'LDAPS';        Port = 636;  TCP = $true;  UDP = $false }
            @{ Name = 'SMB';          Port = 445;  TCP = $true;  UDP = $false }
            @{ Name = 'RPC-EPM';      Port = 135;  TCP = $true;  UDP = $false }
            @{ Name = 'WinRM-HTTP';   Port = 5985; TCP = $true;  UDP = $false }
            @{ Name = 'WinRM-HTTPS';  Port = 5986; TCP = $true;  UDP = $false }
        )
        Timeouts = @{
            Ping           = 3
            Tcp            = 3
            DnsResolve     = 5
            DefaultCommand = 60
            Dcdiag         = 300
            DcdiagPerTest  = 60
            Repadmin       = 120
            W32tm          = 30
        }
    }

    Services = @{
        Required = @('NTDS','DNS','Netlogon','DFSR','W32Time','KDC','LanmanServer')
        Optional = @('LanmanWorkstation','RpcSs','DHCPServer','W3SVC')
        Policy = @{
            NTDS         = @{ MustExist = $true;  MustBeRunning = $true;  Severity = 'Critical' }
            DNS          = @{ MustExist = $false; MustBeRunning = $true;  Severity = 'High'     }
            Netlogon     = @{ MustExist = $true;  MustBeRunning = $true;  Severity = 'Critical' }
            DFSR         = @{ MustExist = $false; MustBeRunning = $true;  Severity = 'High'     }
            W32Time      = @{ MustExist = $true;  MustBeRunning = $true;  Severity = 'Medium'   }
            KDC          = @{ MustExist = $true;  MustBeRunning = $true;  Severity = 'Critical' }
            LanmanServer = @{ MustExist = $true;  MustBeRunning = $true;  Severity = 'Medium'   }
        }
    }

    EventLogs = @{
        DefaultLogs  = @('Directory Service','DNS Server','DFS Replication','System')
        OptionalLogs = @('Security')

        # IDs significant enough to be surfaced as checks.
        SignificantIds = @{
            'Directory Service' = @(1083,1084,1311,1388,1393,1655,1863,1864,1865,1869,1925,1926,1988,2042,2087,2088,2089,2093)
            'DFS Replication'   = @(4004,4012,4602,4604,4612,4614,5002,5008,5012,5014)
            'DNS Server'        = @(4010,4013,4015,4070,4090,4521,4523,4524,6001,6002,6532,6533)
            'System'            = @(5719,5783,1128,1129)
        }

        # IDs known to be cosmetic, self-inflicted, or informational only.
        # Their presence is recorded but they never raise severity.
        AcceptableIds = @{
            'Directory Service' = @(2887,3041)
            'System'            = @(10028,1014)
            'DNS Server'        = @(5504)
            'DFS Replication'   = @()
        }

        # Curated Security log event IDs (only used when -IncludeSecurityLog is set).
        # Kept intentionally narrow to avoid PII exposure.
        SecurityIds = @(4625,4740,4771,4776)

        # Thresholds used to classify per-ID occurrences.
        RecurrenceThreshold = 3      # >= this many Error/Critical => FAIL/High
        WarningBulkThreshold = 5     # >= this many Warning => WARNING/Low
    }

    Dns = @{
        SrvRecords = @(
            '_ldap._tcp.dc._msdcs',
            '_kerberos._tcp',
            '_kerberos._udp',
            '_kpasswd._tcp',
            '_kpasswd._udp',
            '_ldap._tcp',
            '_ldap._tcp.pdc._msdcs',
            '_ldap._tcp.gc._msdcs',
            '_gc._tcp',
            '_ldap._tcp.ForestDnsZones',
            '_ldap._tcp.DomainDnsZones'
        )
    }

    Replication = @{
        StalePartnerDays        = 7
        WarningPartnerDays      = 1
        FailureWarningCount     = 1
        FailureHighCount        = 3
        FailureCriticalCount    = 5
        MinReplicationFrequency = 15
        MaxReplicationFrequency = 1440
        AcceptedTransports      = @('IP','SMTP')
    }

    Dcdiag = @{
        Tests = @(
            @{ Name = 'Connectivity';        Severity = 'Critical'; Required = $true  }
            @{ Name = 'Advertising';         Severity = 'High';     Required = $true  }
            @{ Name = 'Services';            Severity = 'High';     Required = $true  }
            @{ Name = 'Replications';        Severity = 'High';     Required = $true  }
            @{ Name = 'SysVolCheck';         Severity = 'High';     Required = $true  }
            @{ Name = 'NetLogons';           Severity = 'High';     Required = $true  }
            @{ Name = 'FSMOCheck';           Severity = 'High';     Required = $true  }
            @{ Name = 'KnowsOfRoleHolders';  Severity = 'High';     Required = $true  }
            @{ Name = 'MachineAccount';      Severity = 'Medium';   Required = $true  }
            @{ Name = 'SystemLog';           Severity = 'Medium';   Required = $false }
            @{ Name = 'Topology';            Severity = 'Medium';   Required = $true  }
            @{ Name = 'VerifyReferences';    Severity = 'Medium';   Required = $true  }
            @{ Name = 'LocatorCheck';        Severity = 'High';     Required = $true  }
        )
    }

    Reporting = @{
        ToolName    = 'AD Health Check Toolkit'
        Author      = 'Matheus S Santos'
        Version     = '0.1.0'

        Scoring = @{
            BaseScore        = 100
            Weights = @{
                Critical      = 15
                High          = 8
                Medium        = 3
                Low           = 1
                Informational = 0
            }
            UnknownWeightFactor = 0.5

            Bands = @(
                @{ Min = 95; Max = 100; Label = 'Healthy';   Color = '#2e7d32' }
                @{ Min = 80; Max =  94; Label = 'Good';      Color = '#558b2f' }
                @{ Min = 60; Max =  79; Label = 'Attention'; Color = '#f9a825' }
                @{ Min = 40; Max =  59; Label = 'Degraded';  Color = '#ef6c00' }
                @{ Min =  0; Max =  39; Label = 'Critical';  Color = '#c62828' }
            )
        }
    }
}