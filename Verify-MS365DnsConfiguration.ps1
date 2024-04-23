
#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement, DnsClient

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
    PS C:\> .\Verify-MS365DnsConfiguration.ps1 -DomainId example.com | Format-List
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
    [Alias('Name', 'Domain', 'DomainName')]
    [string[]]
    $DomainId,

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

    foreach ($domainName in $DomainId) {
        #region Initialization
        [int] $mismatchCount = 0
        #endregion

        #region Input

        Write-Verbose -Message `
            "Getting service configuration records (desired configuration) for domain $domainName."
        try {
            $serviceConfigurationRecords =  `
                Get-MgDomainServiceConfigurationRecord `
                    -DomainId $domainName -ErrorAction Stop
        }
        catch [Microsoft.Graph.PowerShell.AuthenticationException], [System.Security.Authentication.AuthenticationException] {
            Write-Error 'Authentication needed. Please call Connect-MgGraph -Scopes Domain.Read.All'
            throw $newError
        }
        catch {
            Write-Verbose "Error class: $($PSItem.Exception.GetType())"
            throw
        }
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

            $commonResolveDnsNameParameters = @{
                ErrorAction = 'SilentlyContinue'
                Verbose = $false
            }

            if (-not [String]::IsNullOrWhiteSpace($Server)) {
                $commonResolveDnsNameParameters.Add('Server', $Server)
            }
            
            $dnsName = Resolve-DnsName `
                -Type $serviceConfigurationRecord.RecordType `
                -Name $serviceConfigurationRecord.Label `
                @commonResolveDnsNameParameters
            
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
                        $misMatch = $serviceConfigurationRecord.AdditionalProperties.mailExchange `
                            -ne $dnsName.NameExchange
                        if ($misMatch) {
                            Write-Warning `
                                "MX record $(
                                    $serviceConfigurationRecord.Label
                                ) should point to $(
                                    $serviceConfigurationRecord.AdditionalProperties.mailExchange
                                ), but points to $($dnsName.NameExchange)"
                        }
                    }
                    'Txt' {
                        $misMatch = `
                            $serviceConfigurationRecord.AdditionalProperties.text -notin $dnsName.Strings
                        if ($misMatch) {
                            Write-Warning `
                                "TXT record $($dnsName.Name) does not contain $(
                                    $serviceConfigurationRecord.AdditionalProperties.text
                                )"
                        }
                    }
                    'CName' {
                        $misMatch = $serviceConfigurationRecord.AdditionalProperties.canonicalName `
                            -ne $dnsName.NameHost
                        if ($misMatch) {
                            Write-Warning `
                                "CNAME record $(
                                    $serviceConfigurationRecord.Label
                                ) should point to $(
                                    $serviceConfigurationRecord.AdditionalProperties.canonicalName
                                ), but points to $($dnsName.NameHost)"                
                        }
                    }
                    'Srv' {
                        $misMatch = 
                            $serviceConfigurationRecord.AdditionalProperties.nameTarget `
                            -ne $dnsName.NameTarget
                        $warning = "SRV record $(
                            $serviceConfigurationRecord.Label)
                        "
                        if ($misMatch) {
                            Write-Warning `
                                "$warning NameTarget should be $(
                                    $serviceConfigurationRecord.AdditionalProperties.nameTarget
                                ), but is $($dnsName.NameTarget)"                
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.AdditionalProperties.port `
                                -ne $dnsName.Port
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Port should be $(
                                    $serviceConfigurationRecord.AdditionalProperties.port
                                ), but is $($dnsName.Port)"
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.AdditionalProperties.priority `
                                -ne $dnsName.Priority
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Priority should be $(
                                    $serviceConfigurationRecord.AdditionalProperties.priority
                                ), but is $($dnsName.Priority)"
                        }
                        $misMatch = $misMatch `
                            -or $serviceConfigurationRecord.AdditionalProperties.weight `
                                -ne $dnsName.Weight
                        if ($misMatch) {
                            Write-Warning `
                                "$warning Weight should be $(
                                    $serviceConfigurationRecord.AdditionalProperties.weight
                                ), but is $($dnsName.Weight)"
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
                    $domainName, $serviceConfigurationRecord, $dnsName
                )
            }

            #endregion Output
        }

        #endregion Processing

        #region Output
        if ($mismatchCount -eq 0) {
            Write-Verbose -Message `
                "All records for domain $domainName are fine. Good job!"
        }
        #endregion Output
        
    }

    #endregion Processing
    
    #region Output
    #endregion Output
}

end {
}
