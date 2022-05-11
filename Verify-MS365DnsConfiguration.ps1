
#Requires -Modules AzureAd, DnsClient

<#
.SYNOPSIS
    Verifies the DNS entries for Microsoft 365 services.
.DESCRIPTION
   The script first retrieves the required DNS entries from Azure AD.
   Then it tries to resolve the entries and compares them to the DNS entries retrieved from Azure AD.
.PARAMETER Name
    The name of the the domain to verify.
.PARAMETER Server
    The DNS server to use for verification. Default is the default DNS server of the system.
.EXAMPLE
    PS C:\> .\Verify-MS365DnsConfiguration.ps1 -Name example.com
    Verifies the DNS entries for the domain example.com
.INPUTS
.OUTPUTS
    System.Collections.Generic.List<MS365DnsConfigurationVerificationResult>
    A list of missing or mismatched DNS entries.
    MS365DnsConfigurationVerificationResult is a type with the properties ShouldBe and Is.
    ShouldBe contains the object returned by Get-AzureADDomainServiceConfigurationRecord.
    Is contains the object returned by Resolve-DnsName. If the name cannot be resolved, it contains $null.
.NOTES
    Authenticate to Azure AD first using Connect-AzureAD.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('Name', 'Domain')]
    [string[]]
    $DomainName,

    [string]
    $Server
)

begin {
    class MS365DnsConfigurationVerificationResult {
        $ShouldBe
        $Is
        [String]$DomainName

        MS365DnsConfigurationVerificationResult([String]$DomainName) {
            $this.DomainName = $DomainName
            $this.ShouldBe = $null
            $this.Is = $null
        }

        MS365DnsConfigurationVerificationResult(
            [String]$DomainName, $ShouldBe
        ) {
            $this.DomainName = $DomainName
            $this.ShouldBe = $ShouldBe
            $this.Is = $null
        }

        MS365DnsConfigurationVerificationResult (
            [String]$DomainName, $ShouldBe, $Is
        ) {
            $this.DomainName = $DomainName
            $this.ShouldBe = $ShouldBe
            $this.Is = $Is
            $this.Is = $this | Select-Object -ExpandProperty Is
        }
    }

    # Connect-AzureAD
}

process {
    #region Input
    #endregion Input

    #region Processing

    foreach ($name in $DomainName) {
        #region Initialization
        [int] $mismatchCount = 0
        #endregion

        #region Input

        Write-Verbose -Message `
            "Getting service configuration records (desired configuration) for domain $name."
        $serviceConfigurationRecords =  `
            Get-AzureADDomainServiceConfigurationRecord -Name $name

        #endregion Input

        #region Processing

        foreach ($serviceConfigurationRecord in $serviceConfigurationRecords) {
            #region Initialization

            $dnsName = $null
            [bool]$misMatch = $false
            
            #endregion Initialization

            #region Input
            
            Write-Verbose -Message `
                "Resolving $($serviceConfigurationRecord.RecordType) record $($serviceConfigurationRecord.Label)"

            if ($Server -eq '') {
                $dnsName = Resolve-DnsName `
                    -Type $serviceConfigurationRecord.RecordType `
                    -Name $serviceConfigurationRecord.Label `
                    -ErrorAction SilentlyContinue `
                    -Verbose:$false
            }

            if ($Server -ne '') {
                $dnsName = Resolve-DnsName `
                    -Type $serviceConfigurationRecord.RecordType `
                    -Name $serviceConfigurationRecord.Label `
                    -Server $Server `
                    -ErrorAction SilentlyContinue `
                    -Verbose:$false
            }
            
            #endregion Input
            
            #region Processing

            # Missing record
            $misMatch = $null -eq $dnsName
            if ($misMatch) {
                Write-Warning "Missing record $serviceConfigurationRecord"
            }

            # Mismatched records
            if (-not $misMatch) {
                switch ($serviceConfigurationRecord.RecordType) {
                    'Mx' {
                        $misMatch = $serviceConfigurationRecord.MailExchange `
                            -ne $dnsName.NameExchange
                        if ($misMatch) {
                            Write-Warning `
                                "MX record $($serviceConfigurationRecord.Label) should point to $($serviceConfigurationRecord.MailExchange), but points to $($dnsName.NameExchange)"
                        }
                    }
                    'Txt' {
                        $misMatch = `
                            $serviceConfigurationRecord.Text -notin $dnsName.Strings
                        if ($misMatch) {
                            Write-Warning `
                                "TXT record $($dnsName.Name) does not contain $($serviceConfigurationRecord.Text)"
                        }
                    }
                    'CName' {
                        $misMatch = $serviceConfigurationRecord.CanonicalName `
                            -ne $dnsName.NameHost
                        if ($misMatch) {
                            Write-Warning `
                                "CNAME record $($serviceConfigurationRecord.Label) should point to $($serviceConfigurationRecord.CanonicalName), but points to $($dnsName.NameHost)"                
                        }
                    }
                    'Srv' {
                        $misMatch = 
                            $serviceConfigurationRecord.NameTarget `
                            -ne $dnsName.NameTarget
                        $warning = "SRV record $($serviceConfigurationRecord.Label)"
                        if ($misMatch) {
                            Write-Warning `
                                "$warning NameTarget should be $($serviceConfigurationRecord.NameTarget), but is $($dnsName.NameTarget)"                
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.Port -ne $dnsName.Port
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Port should be $($serviceConfigurationRecord.Port), but is $($dnsName.Port)"
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.Priority -ne $dnsName.Priority
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Priority should be $($serviceConfigurationRecord.Priority), but is $($dnsName.Priority)"
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.Weight -ne $dnsName.Weight
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Weight should be $($serviceConfigurationRecord.Weight), but is $($dnsName.Weight)"
                        }
                    }
                    Default {}
                }        
            }
            
            #endregion Processing

            #region Output
            
            if ($misMatch) {
                $mismatchCount++
                [MS365DnsConfigurationVerificationResult]::new(
                    $name, $serviceConfigurationRecord, $dnsName
                )
            }

            #endregion Output
        }

        #endregion Processing

        #region Output
        if ($mismatchCount -eq 0) {
            Write-Verbose -Message `
                "All records for domain $name are fine. Good job!"
        }
        #endregion Output
        
    }

    #endregion Processing
    
    #region Output
    #endregion Output
}

end {
}
