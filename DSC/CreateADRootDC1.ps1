configuration CreateADRootDC1
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,
        
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds
    )

    Import-DscResource -ModuleName xActiveDirectory, xStorage, xNetworking, cDisk
    
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }
        
        WindowsFeature DNS
        {
            Ensure = "Present"
            Name = "DNS"
        }
        
        WindowsFeature DnsTools
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }
        
        Script SetDNSForwarder
        {
            #
            # 
            #
            SetScript =
            {
                $dnsrunning = $false
                $triesleft = $Using:RetryCount
                While (-not $dnsrunning -and ($triesleft -gt 0))
                {
                    $triesleft--
                    try
                    {
                        $dnsrunning = (Get-Service -name dns).Status -eq "running"
                    } catch {
                        $dnsrunning = $false
                    }
                    if (-not $dnsrunning)
                    {
                        Write-Verbose -Verbose "Waiting $($Using:RetryIntervalSec) seconds for DNS service to start"
                        Start-Sleep -Seconds $Using:RetryIntervalSec
                    }
                }

                if (-not $dnsrunning)
                {
                    Write-Warning "DNS service is not running, cannot edit forwarder. Template deployment will fail."
                    # but continue anyway.
                }
                $forwarderlist = "168.63.129.16"
                <#try {
                    Write-Verbose -Verbose "Getting list of DNS forwarders"
                    $forwarderlist = "168.63.129.16"
                 <#
                    if ($forwarderlist.IPAddress)
                    { 
                        Write-Verbose -Verbose "Removing forwarders"
                        Remove-DnsServerForwarder -IPAddress $forwarderlist.IPAddress -Force
                    } else {
                        Write-Verbose -Verbose "No forwarders found"
                    }
                } catch {
                    Write-Warning -Verbose "Exception running Remove-DNSServerForwarder: $_"
                }
		        #>
                try {
                    Write-Verbose -Verbose "setting DNS forwarder to $forwarderlist"
                    Set-DnsServerForwarder -IPAddress $forwarderlist -PassThru
                } catch {
                    Write-Warning -Verbose "Exception running Set-DNSServerForwarder: $_"
                }
                 
            }
            GetScript =  { @{} }
            TestScript = { $false }
            DependsOn = "[WindowsFeature]DNSTools"
        }
      
        WindowsFeature ADTools
        {
            Ensure = "Present"
            Name = "RSAT-AD-Tools"
            DependsOn = "[WindowsFeature]DNS"
        }
        
        WindowsFeature GPOTools
        {
            Ensure = "Present"
            Name = "GPMC"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature DFSTools
        {
            Ensure = "Present"
            Name = "RSAT-DFS-Mgmt-Con"
            DependsOn = "[WindowsFeature]DNS"
        }

        xWaitforDisk Disk0
        {
            DiskID = 0
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }
        
        cDiskNoRestart ADDataDisk
        {
            DiskNumber = 0
            DriveLetter = "C"
            DependsOn = "[xWaitForDisk]Disk0"
        }
        
        WindowsFeature ADDSInstall
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            DependsOn = "[cDiskNoRestart]ADDataDisk"
        }

        #
        # make sure the machine looks to itself for DNS now.
        #
        xDnsServerAddress DnsServerAddress
        {
            Address        = '127.0.0.1'
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNS"
        }

        xADDomain FirstDS
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "c:\NTDS"
            LogPath = "c:\NTDS"
            SysvolPath = "c:\SYSVOL"
            DependsOn = @("[WindowsFeature]ADDSInstall", "[xDnsServerAddress]DnsServerAddress", "[Script]SetDNSForwarder")
        }
    }
}