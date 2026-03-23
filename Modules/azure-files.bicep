// ============================================================
// modules/azure-files.bicep
// Azure Storage Account with SMB File Share
// Private Endpoint + Private DNS Zone for secure access
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────
param location string
param suffix string
param tags object

param storageSubnetId string
param vnetId string

@description('SMB file share name (e.g. profiles, redirects)')
param fileShareName string = 'profiles'

@description('File share quota in GB')
param fileShareQuotaGb int = 512

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Premium_LRS', 'Premium_ZRS'])
param storageSkuName string = 'Standard_LRS'

// Premium file shares require FileStorage kind
var isPremium = startsWith(storageSkuName, 'Premium')
var storageKind = isPremium ? 'FileStorage' : 'StorageV2'
var fileShareTier = isPremium ? 'Premium' : 'TransactionOptimized'

// Storage account names must be 3-24 chars, lowercase alphanumeric only
// Build a deterministic short name from the suffix
var saRaw = replace(replace(toLower('st${suffix}'), '-', ''), '_', '')
var storageAccountName = length(saRaw) > 24 ? substring(saRaw, 0, 24) : saRaw

// ── Storage Account ───────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: storageKind
  sku: {
    name: storageSkuName
  }
  properties: {
    // Disable public access; all access via private endpoint
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true           // Required for domain-join script; restrict post-setup if needed
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true

    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }

    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }

    // largeFileSharesState と azureFilesIdentityBasedAuthentication は
    // ストレージアカウント作成後にポータルまたはスクリプトで設定する
    // （作成時に同時設定するとリージョンによって FeatureNotSupportedOnStorageAccount エラーになる）
  }
}

// ── File Service ──────────────────────────────────────────────
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    // SMB hardening (versions, kerberosTicketEncryption 等) は
    // Premium tier のみサポート。Standard では省略する。
    protocolSettings: isPremium ? {
      smb: {
        versions: 'SMB3.0;SMB3.1.1'
        authenticationMethods: 'NTLMv2;Kerberos'
        kerberosTicketEncryption: 'AES-256'
        channelEncryption: 'AES-128-CCM;AES-128-GCM;AES-256-GCM'
        multichannel: {
          enabled: true
        }
      }
    } : {}
  }
}

// ── File Share ────────────────────────────────────────────────
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: fileShareQuotaGb
    accessTier: fileShareTier
    enabledProtocols: 'SMB'
  }
}

// ── Private DNS Zone – file.core.windows.net ──────────────────
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-${suffix}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// ── Private Endpoint ──────────────────────────────────────────
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${storageAccountName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: storageSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountName}-file'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['file']
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-file'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
output privateEndpointId string = privateEndpoint.id
output fileEndpoint string = storageAccount.properties.primaryEndpoints.file
