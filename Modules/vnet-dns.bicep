// ============================================================
// modules/vnet-dns.bicep
// VNet のカスタム DNS サーバーを Entra DS の DC IP に更新する
//
// 【なぜ必要か】
// デフォルトでは VNet の DNS は Azure 提供の DNS（168.63.129.16）を使用する。
// Entra DS のドメインに VM を参加させるには、VNet の DNS サーバーを
// AADDS のドメインコントローラー IP に変更する必要がある。
// AADDS の DC IP はプロビジョニング完了後にのみ確定するため、
// AADDS デプロイ後に本モジュールで VNet を更新する。
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────
@description('更新対象の VNet 名')
param vnetName string

@description('VNet のリージョン（network モジュールと同じ location を渡す）')
param location string

@description('VNet に適用するタグ')
param tags object

@description('VNet のアドレス空間（network モジュールの vnetAddressPrefix を渡す）')
param vnetAddressPrefix string

@description('AADDS ドメインコントローラーの IP アドレス一覧（entra-ds モジュールの output から取得）')
param dnsServers array

@description('AVD サブネットの CIDR')
param avdSubnetPrefix string

@description('AADDS サブネットの CIDR')
param aadsSubnetPrefix string

@description('Storage サブネットの CIDR')
param storageSubnetPrefix string

@description('AVD 用 NSG のリソース ID')
param avdNsgId string

@description('AADDS 用 NSG のリソース ID')
param aadsNsgId string

@description('Storage 用 NSG のリソース ID')
param storageNsgId string

// ── VNet DNS サーバーの更新 ───────────────────────────────────
// location・tags・subnets をパラメーターで明示することで BCP120 を回避する
resource vnetDnsUpdate 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    dhcpOptions: {
      dnsServers: dnsServers
    }
    subnets: [
      {
        name: 'snet-avd'
        properties: {
          addressPrefix: avdSubnetPrefix
          networkSecurityGroup: { id: avdNsgId }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-aadds'
        properties: {
          addressPrefix: aadsSubnetPrefix
          networkSecurityGroup: { id: aadsNsgId }
        }
      }
      {
        name: 'snet-storage'
        properties: {
          addressPrefix: storageSubnetPrefix
          networkSecurityGroup: { id: storageNsgId }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────
output dnsServers array = vnetDnsUpdate.properties.dhcpOptions.dnsServers
