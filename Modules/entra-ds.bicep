// ============================================================
// modules/entra-ds.bicep
// Microsoft Entra Domain Services (formerly Azure AD DS)
// Managed domain for Kerberos / NTLM authentication with AVD
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────
param location string
param suffix string
param tags object

@description('DNS domain name for the managed domain (e.g. aadds.contoso.local)')
param domainName string

@description('AADDS SKU: Standard | Enterprise | Premium')
@allowed(['Standard', 'Enterprise', 'Premium'])
param sku string = 'Enterprise'

@description('Resource ID of the AADDS-dedicated subnet')
param aadsSubnetId string

@description('Enable LDAPS (Secure LDAP). Requires a valid PFX certificate post-deployment.')
param enableLdaps bool = false

@description('Enable NTLM and Kerberos password-hash synchronisation for cloud-only users')
param syncType string = 'All' // 'All' or 'CloudOnly'

// ── Entra Domain Services Managed Domain ──────────────────────
resource aadds 'Microsoft.AAD/domainServices@2022-12-01' = {
  name: domainName
  location: location
  tags: tags
  properties: {
    domainName: domainName
    sku: sku
    filteredSync: syncType == 'CloudOnly' ? 'Enabled' : 'Disabled'

    domainSecuritySettings: {
      ntlmV1: 'Disabled'
      tlsV1: 'Disabled'
      syncNtlmPasswords: 'Enabled'       // Required for Azure Files Kerberos auth
      syncKerberosPasswords: 'Enabled'   // Required for Kerberos ticket issuance
      syncOnPremPasswords: 'Enabled'
      kerberosRc4Encryption: 'Disabled'  // Prefer AES-256
      kerberosArmoring: 'Enabled'
    }

    ldapsSettings: {
      ldaps: enableLdaps ? 'Enabled' : 'Disabled'
      // externalAccess and pfxCertificate must be set post-deployment if enableLdaps = true
    }

    notificationSettings: {
      notifyGlobalAdmins: 'Enabled'
      notifyDcAdmins: 'Enabled'
      additionalRecipients: []
    }

    replicaSets: [
      {
        location: location
        subnetId: aadsSubnetId
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────
output aaddsId string = aadds.id
output domainName string = aadds.properties.domainName
output domainControllerIpAddresses array = aadds.properties.replicaSets[0].domainControllerIpAddress
