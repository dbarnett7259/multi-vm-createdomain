Configuration CreateADRootDC1_v2
{
    Param ( 
        [String]$DomainName,
        [System.Management.Automation.PSCredential]$AdminCreds,
        [System.Management.Automation.PSCredential]$AdminSafemodeCreds,
        [Int]$RetryCount = 30,
        [Int]$RetryIntervalSec = 120
    )

    Import-DscResource -ModuleName ActiveDirectoryDSC, NetworkingDSC, PendingReboot, computermanagementDSC #, PSDesiredStateConfiguration


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
        
        ADDomain DC1
        {
            DomainName = $DomainName
			Credential = $DomainCreds
			SafemodeAdministratorPassword = $SafemodeCreds
			DatabasePath = 'C:\Windows\NTDS'
			LogPath = 'C:\Windows\NTDS'
			SysvolPath = 'C:\Windows\SYSVOL'
			DomainNetbiosName = $DomainName.Split('.')[0]
            DependsOn = '[WindowsFeature]InstallADDS'
            
        }
        
        <#ADForestProperties ForestProps
		#{
			ForestName = $DomainName
			UserPrincipalNameSuffixToAdd = $UserPrincipalName
			DependsOn = @('[xADDomain]DC1')
		}
        #>
        
        IEEnhancedSecurityConfiguration 'DisableForAdministrators'
        {
            Role    = 'Administrators'
            Enabled = $false
        }

        IEEnhancedSecurityConfiguration 'DisableForUsers'
        {
            Role    = 'Users'
            Enabled = $false
        }
        
        Registry HideServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
            ValueName = 'DoNotOpenServerManagerAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Ensure = 'Present'
            Force = $true
			DependsOn = '[ADDomain]DC1'
		}

        Registry HideInitialServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe'
            ValueName = 'DoNotOpenInitialConfigurationTasksAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Ensure = 'Present'
            Force = $true
			DependsOn = '[ADDomain]DC1'
		}

        Script TurnOnNetworkDiscovery
        {
            SetScript = 
            {
                Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Any' -Enabled true
            }
            GetScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                if ($null -eq $fwRules)
                {
                    return @{result = $false}
                }
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return @{
                    result = $result
                }
            }
            TestScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                if ($null -eq $fwRules)
                {
                    return $false
                }
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return $result
            }
			DependsOn = '[ADDomain]DC1'
        }
        
        Script TurnOnFileSharing
        {
            SetScript = 
            {
                Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' | Set-NetFirewallRule -Profile 'Any' -Enabled true
            }
            GetScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return @{
                    result = $result
                }
            }
            TestScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return $result
            }
			DependsOn = '[ADDomain]DC1'
        }

        #region Enable TLS1.2
        # REF: https://support.microsoft.com/en-us/help/3140245/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-wi
        # Enable TLS 1.2 SChannel
        Registry EnableTls12ServerEnabled
        {
            Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
            ValueName = 'DisabledByDefault'
            ValueType = 'Dword'
            ValueData = 0
			Ensure = 'Present'
			Force = $true
        }
        # Enable Internet Settings
        Registry EnableTlsInternetExplorerLM
        {
            Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
            ValueName = 'SecureProtocols'
            ValueType = 'Dword'
            ValueData = '0xA80'
            Ensure = 'Present'
			Hex = $true
			Force = $true
        }
        #enable for WinHTTP
        Registry EnableTls12WinHttp
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
            ValueName = 'DefaultSecureProtocols'
            ValueType = 'Dword'
            ValueData = '0x00000800'
            Ensure = 'Present'
			Hex = $true
			Force = $true
        }
        Registry EnableTls12WinHttp64
        {
            Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
            ValueName = 'DefaultSecureProtocols'
            ValueType = 'Dword'
            ValueData = '0x00000800'
            Hex = $true
			Ensure = 'Present'
			Force = $true
        }
        #powershell defaults
        Registry SchUseStrongCrypto
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
            ValueName = 'SchUseStrongCrypto'
            ValueType = 'Dword'
            ValueData =  '1'
			Ensure = 'Present'
			Force = $true
        }
        Registry SchUseStrongCrypto64
        {
            Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'
            ValueName = 'SchUseStrongCrypto'
            ValueType = 'Dword'
            ValueData =  '1'
			Ensure = 'Present'
			Force = $true
        }
        #endregion


		#region COE
		
        # when the DC is promoted the DNS (static server IP's) are automatically set to localhost (127.0.0.1 and ::1) by DNS
        # I have to remove those static entries and just use the Azure Settings for DNS from DHCP
        Script ResetDNS
        {
            DependsOn = '[ADDomain]DC1'
            GetScript  = { @{Name = 'DNSServers'; Address = { Get-DnsClientServerAddress -InterfaceAlias Ethernet* | foreach ServerAddresses } } }
            SetScript  = { Set-DnsClientServerAddress -InterfaceAlias Ethernet* -ResetServerAddresses -Verbose }
            TestScript = { Get-DnsClientServerAddress -InterfaceAlias Ethernet* -AddressFamily IPV4 | 
                    Foreach { ! ($_.ServerAddresses -contains '127.0.0.1') } }
        }
        	
     }
}