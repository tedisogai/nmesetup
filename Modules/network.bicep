// ============================================================
// modules/network.bicep
// Virtual Network, Subnets, NSGs, and Route Tables
// for Nerdio Manager for Enterprise + AVD Host Pools
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────
param location string
param suffix string
param tags object

param vnetAddressPrefix string
param avdSubnetPrefix string
param aadsSubnetPrefix string
param storageSubnetPrefix string

// ── NSG – AVD Host Pool ───────────────────────────────────────
resource avdNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-avd-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-AVD-ServiceTag-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'WindowsVirtualDesktop'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Allow AVD service traffic'
        }
      }
      {
        name: 'Allow-RDP-From-VNet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Allow RDP management from within VNet'
        }
      }
      {
        name: 'Allow-SMB-From-AVD'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: avdSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '445'
          description: 'Allow SMB (Azure Files) from AVD hosts'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// ── NSG – Entra Domain Services ───────────────────────────────
// Microsoft-required rules for AADDS: https://learn.microsoft.com/azure/active-directory-domain-services/alert-nsg
resource aadsNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-aadds-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSyncWithAzureAD'
        properties: {
          priority: 101
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Required: allow AADDS sync with Azure AD'
        }
      }
      {
        name: 'AllowRD'
        properties: {
          priority: 201
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'CorpNetSaw'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Required: Microsoft secure access workstation RDP'
        }
      }
      {
        name: 'AllowPSRemoting'
        properties: {
          priority: 301
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5986'
          description: 'Required: allow PS remoting for AADDS management'
        }
      }
      {
        name: 'AllowLDAPS'
        properties: {
          priority: 401
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '636'
          description: 'Allow Secure LDAP (LDAPS) – restrict source to known IPs if enabled'
        }
      }
    ]
  }
}

// ── NSG – Storage / Private Endpoint ─────────────────────────
resource storageNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-storage-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SMB-From-AVD'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: avdSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '445'
          description: 'Allow SMB from AVD session hosts'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// ── Virtual Network ───────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${suffix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-avd'
        properties: {
          addressPrefix: avdSubnetPrefix
          networkSecurityGroup: { id: avdNsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-aadds'
        properties: {
          addressPrefix: aadsSubnetPrefix
          networkSecurityGroup: { id: aadsNsg.id }
          // AADDS requires this subnet to have no service endpoints or delegations
        }
      }
      {
        name: 'snet-storage'
        properties: {
          addressPrefix: storageSubnetPrefix
          networkSecurityGroup: { id: storageNsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ── Subnet の個別参照（existing）────────────────────────────────
// vnet.properties.subnets[N].id はランタイムで正しく解決されないケースがあるため
// existing resource として明示的に参照することで確実にIDを取得する

resource snetAvd 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: 'snet-avd'
}

resource snetAadds 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: 'snet-aadds'
}

resource snetStorage 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: 'snet-storage'
}

// ── Outputs ───────────────────────────────────────────────────
output vnetId string = vnet.id
output vnetName string = vnet.name
output avdSubnetId string = snetAvd.id
output aadsSubnetId string = snetAadds.id
output storageSubnetId string = snetStorage.id
