# Verify-MS365DnsConfiguration

Script to verify the DNS records for Microsoft 365 services.

## Description

The script first retrieves the required DNS entries from Azure AD. Then it tries to resolve the entries and compares them to the DNS entries retrieved from Azure AD.

## Parameters

### Name

The name of the the domain to verify.

### Server

The DNS server to use for verification. Default is the default DNS server of the system.

## Example

```powershell
.\Verify-MS365DnsConfiguration.ps1 -DomainId example.com | Format-List
```

Verifies the DNS entries for the domain example.com

## Outputs

```powershell
System.Collections.Generic.List\<MS365DnsConfigurationVerificationResult\>
```

A list of missing or mismatched DNS entries.

`MS365DnsConfigurationVerificationResult` is a type with the properties `ShouldBe` and `Is`.
`ShouldBe` contains the object returned by `Get-AzureADDomainServiceConfigurationRecord`.
`Is` contains the object returned by `Resolve-DnsName`. If the name cannot be resolved, it contains `$null`.

## Notes

Authenticate to Azure AD first using `Connect-AzureAD`.
