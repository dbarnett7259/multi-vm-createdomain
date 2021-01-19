Configuration CreateADRootDC1
{
    Param ( 
        [String]$DomainName,
        [PSCredential]$AdminCreds,
        [Int]$RetryCount = 30,
        [Int]$RetryIntervalSec = 120
    )

    Import-DscResource -ModuleName xActiveDirectory, xNetworking, PSDesiredStateConfiguration, xPendingReboot
    
    $ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
            PsDscAllowDomainUser = $true
        })
    }
    
    Function IIf
    {
        param($If, $IfTrue, $IfFalse)
        
        If ($If -IsNot "Boolean") { $_ = $If }
        If ($If) { If ($IfTrue -is "ScriptBlock") { &$IfTrue } Else { $IfTrue } }
        Else { If ($IfFalse -is "ScriptBlock") { &$IfFalse } Else { $IfFalse } }
    }

    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

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

        WindowsFeature InstallADDS
        {            
            Ensure = "Present"
            Name   = "AD-Domain-Services"
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
        if ($Node.WindowsFeatureSetAbsent)
        {
            WindowsFeatureSet WindowsFeatureSetAbsent
            {
                Ensure = 'Absent'
                Name   = $Node.WindowsFeatureSetAbsent
            }
        }

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
            DependsOn                         = "[xADDomain]DC1"
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
}#Main


<# OLD CONFIG SCRIPT
configuration CreateADRootDC1 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    ) 
    Import-DscResource -ModuleName xActiveDirectory, xNetworking, PSDesiredStateConfiguration, xPendingReboot
     
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)

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

        Script EnableDNSDiags
	    {
      	    SetScript = { 
		        Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
	        DependsOn = "[WindowsFeature]DNS"
        }

	    WindowsFeature DnsTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
	    }

        xDnsServerAddress DnsServerAddress 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
	        DependsOn = "[WindowsFeature]DNS"
        }
        
        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
	    DependsOn="[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
         
        xADDomain DC1 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
	    DependsOn = @("[WindowsFeature]ADDSInstall")
        }
         
         xWaitForADDomain DC1Forest
        {
            DomainName           = $DomainName
            DomainUserCredential = $DomainCreds
            RetryCount           = $RetryCount
            RetryIntervalSec     = $RetryIntervalSec
            DependsOn            = "[xADDomain]DC1"
        } 
        
        xADRecycleBin RecycleBin
        {
            EnterpriseAdministratorCredential = $DomainCreds
            ForestFQDN                        = $DomainName
            DependsOn                         = '[xWaitForADDomain]DC1Forest'
        }

        # borrowed from https://github.com/brwilkinson/AzureDeploymentFramework/blob/main/ADF/ext-DSC/DSC-ADPrimary.ps1#L156
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

        xPendingReboot RebootDC
        {
            Name = "RebootforDCPromo"
            DependsOn = '[Script]ResetDNS'
        }
   }
} 
#>