Configuration CreateADRootDC1
{
    Param ( 
        [String]$DomainName,
        [PSCredential]$AdminCreds,
        [Int]$RetryCount = 30,
        [Int]$RetryIntervalSec = 120
    )

    Import-DscResource -ModuleName xActiveDirectory, xNetworking, PSDesiredStateConfiguration, xPendingReboot

    Function IIf
    {
        param($If, $IfTrue, $IfFalse)
        
        If ($If -IsNot "Boolean") { $_ = $If }
        If ($If) { If ($IfTrue -is "ScriptBlock") { &$IfTrue } Else { $IfTrue } }
        Else { If ($IfFalse -is "ScriptBlock") { &$IfFalse } Else { $IfFalse } }
    }

    $NetBios = $(($DomainName -split '\.')[0])
    [PSCredential]$DomainCreds = [PSCredential]::New($NetBios + '\' + $(($AdminCreds.UserName -split '\\')[-1]), $AdminCreds.Password)

    $credlookup = @{
        "localadmin"  = $AdminCreds
        "DomainCreds" = $DomainCreds
        "DomainJoin"  = $DomainCreds
        }
    
    Node localhost
    {
        LocalConfigurationManager
        {
            ActionAfterReboot    = 'ContinueConfiguration'
            ConfigurationMode    = 'ApplyAndMonitor'
            RebootNodeIfNeeded   = $true
            AllowModuleOverWrite = $true
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
                
        WindowsFeature ActiveDirectory {
            Name = 'AD-Domain-Services'
            Ensure = 'Present'
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSAT-AD-Tools {
            Name = 'RSAT-AD-Tools'
            Ensure = 'Present'
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSAT-ADDS {
            Name = 'RSAT-ADDS'
            Ensure = 'Present'
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSAT-AD-AdminCenter {
            Name = 'RSAT-AD-AdminCenter'
            Ensure = 'Present'
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSAT-ADDS-Tools {
            Name = 'RSAT-ADDS-Tools'
            Ensure = 'Present'
            DependsOn = "[WindowsFeature]DNS"
        }
        
        WindowsFeature GPOTools
        {
            Ensure = "Present"
            Name = "GPMC"
            DependsOn = "[WindowsFeature]DNS"
        }
   
        WindowsFeature InstallADDS
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            DependsOn = "[WindowsFeature]DNS"
        }

        #-------------------------------------------------------------------
        foreach ($Feature in $Node.WindowsFeaturePresent)
        {
            WindowsFeature $Feature
            {
                Name                 = $Feature
                Ensure               = 'Present'
                IncludeAllSubFeature = $true
                #Source = $ConfigurationData.NonNodeData.WindowsFeatureSource
            }
            $dependsonFeatures += @("[WindowsFeature]$Feature")
        }

        #-------------------------------------------------------------------
        
        xADDomain DC1
        {
            DomainName                    = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath                  = 'C:\NTDS'
            LogPath                       = 'C:\NTDS'
            SysvolPath                    = 'C:\SYSVOL'
            DependsOn                     = "[WindowsFeature]InstallADDS"
        }

        xADRecycleBin RecycleBin
        {
            EnterpriseAdministratorCredential = $DomainCreds
            ForestFQDN                        = $DomainName
        }

        # when the DC is promoted the DNS (static server IP's) are automatically set to localhost (127.0.0.1 and ::1) by DNS
        # I have to remove those static entries and just use the Azure Settings for DNS from DHCP
        Script ResetDNS
        {
            DependsOn  = '[xADRecycleBin]RecycleBin'
            GetScript  = { @{Name = 'DNSServers'; Address = { Get-DnsClientServerAddress -InterfaceAlias Ethernet* | foreach ServerAddresses } } }
            SetScript  = { Set-DnsClientServerAddress -InterfaceAlias Ethernet* -ResetServerAddresses -Verbose }
            TestScript = { Get-DnsClientServerAddress -InterfaceAlias Ethernet* -AddressFamily IPV4 | 
                    Foreach { ! ($_.ServerAddresses -contains '127.0.0.1') } }
        }

        #-------------------
        	
        # Need to make sure the DC reboots after it is promoted.
        xPendingReboot RebootForPromo
        {
            Name      = 'RebootForDJoin'
            DependsOn = '[Script]ResetDNS'
        }

     }
}
