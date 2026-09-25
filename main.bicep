// ============================================================
// main.bicep
// Nerdio Manager for Enterprise - Azure Infrastructure
// Deploys: Resource Groups, VNet, Entra DS, Azure Files SMB
// ============================================================

targetScope = 'subscription'

// ── Parameters ───────────────────────────────────────────────
@description('Azure region for all resources')
param location string = 'japaneast'

@description('Environment prefix (e.g. prod, dev, uat)')
@maxLength(8)
param environmentPrefix string = 'prod'

@description('Project / tenant short name used in resource naming')
@maxLength(10)
param projectName string = 'nerdio'

@description('Address space for the entire VNet')
param vnetAddressPrefix string = '10.10.0.0/16'

@description('Subnet for AVD Host Pools (session hosts)')
param avdSubnetPrefix string = '10.10.2.0/24'

@description('Subnet delegated to Entra Domain Services')
param aadsSubnetPrefix string = '10.10.3.0/24'

@description('Subnet for Azure Files / private endpoints')
param storageSubnetPrefix string = '10.10.4.0/24'

@description('Deploy Microsoft Entra Domain Services (managed domain). Set to false to skip AADDS entirely.')
param deployEntraDs bool = true

@description('DNS domain name for Entra Domain Services')
param aadsDomainName string = 'aadds.contoso.local'

@description('SKU for the Entra Domain Services managed domain (Standard or Enterprise or Premium)')
@allowed(['Standard', 'Enterprise', 'Premium'])
param aadsSku string = 'Enterprise'

@description('Azure Compute Gallery name (letters, numbers, periods, underscores only). Leave empty to auto-generate from environmentPrefix/projectName.')
param galleryName string = ''

@description('Azure Files SMB share name')
param fileShareName string = 'profiles'

@description('Azure Files quota in GB')
param fileShareQuotaGb int = 512

@description('Storage account SKU for Azure Files')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Premium_LRS', 'Premium_ZRS'])
param storageSkuName string = 'Standard_LRS'

@description('Tags applied to every resource')
param tags object = {
  environment: environmentPrefix
  project: projectName
  managedBy: 'Bicep'
}

// ── Naming helpers ────────────────────────────────────────────
var suffix = '${environmentPrefix}-${projectName}'
var rgName = 'rg-${suffix}'                        // 共有インフラ用 RG（VNet / AADDS / Storage / Compute Gallery）
var nerdioRgName = 'rg-${suffix}-app'              // Nerdio Manager インストール用 RG
var galleryNameResolved = empty(galleryName) ? 'gal_${replace(suffix, '-', '_')}' : galleryName

// ── Resource Groups ───────────────────────────────────────────
// 共有インフラ用リソースグループ
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: union(tags, { purpose: 'shared-infrastructure' })
}

// Nerdio Manager アプリケーション用リソースグループ
resource nerdioResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: nerdioRgName
  location: location
  tags: union(tags, { purpose: 'nerdio-manager-app' })
}

// ── Module deployments ────────────────────────────────────────
module networkModule 'modules/network.bicep' = {
  name: 'deploy-network'
  scope: resourceGroup
  params: {
    location: location
    suffix: suffix
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    avdSubnetPrefix: avdSubnetPrefix
    aadsSubnetPrefix: aadsSubnetPrefix
    storageSubnetPrefix: storageSubnetPrefix
  }
}

module aadsModule 'modules/entra-ds.bicep' = if (deployEntraDs) {
  name: 'deploy-entra-ds'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    domainName: aadsDomainName
    sku: aadsSku
    aadsSubnetId: networkModule.outputs.aadsSubnetId
  }
}

module storageModule 'modules/azure-files.bicep' = {
  name: 'deploy-azure-files'
  scope: resourceGroup
  params: {
    location: location
    suffix: suffix
    tags: tags
    storageSubnetId: networkModule.outputs.storageSubnetId
    vnetId: networkModule.outputs.vnetId
    fileShareName: fileShareName
    fileShareQuotaGb: fileShareQuotaGb
    storageSkuName: storageSkuName
  }
}

// ── VNet カスタム DNS 更新 ─────────────────────────────────────
// AADDS プロビジョニング完了後に DC の IP を VNet の DNS サーバーとして設定する
// dependsOn により AADDS デプロイ完了後に実行されることを保証する
// deployEntraDs = false の場合は AADDS 自体が存在しないためスキップする
module vnetDnsModule 'modules/vnet-dns.bicep' = if (deployEntraDs) {
  name: 'deploy-vnet-dns'
  scope: resourceGroup
  params: {
    vnetName: networkModule.outputs.vnetName
    location: location
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    dnsServers: aadsModule!.outputs.domainControllerIpAddresses
    avdSubnetPrefix: avdSubnetPrefix
    aadsSubnetPrefix: aadsSubnetPrefix
    storageSubnetPrefix: storageSubnetPrefix
    avdNsgId: networkModule.outputs.avdNsgId
    aadsNsgId: networkModule.outputs.aadsNsgId
    storageNsgId: networkModule.outputs.storageNsgId
  }
}

// ── Azure Compute Gallery ─────────────────────────────────────
// Nerdio Manager が管理するゴールデンイメージ用の共有ギャラリー
module galleryModule 'modules/compute-gallery.bicep' = {
  name: 'deploy-compute-gallery'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    galleryName: galleryNameResolved
  }
}

// ── Outputs ───────────────────────────────────────────────────
output resourceGroupName string = resourceGroup.name
output nerdioResourceGroupName string = nerdioResourceGroup.name
output vnetId string = networkModule.outputs.vnetId
output avdSubnetId string = networkModule.outputs.avdSubnetId
output aadsSubnetId string = networkModule.outputs.aadsSubnetId
output storageSubnetId string = networkModule.outputs.storageSubnetId
output storageAccountName string = storageModule.outputs.storageAccountName
output fileShareName string = storageModule.outputs.fileShareName
output deployEntraDs bool = deployEntraDs
output aadsDomainName string = deployEntraDs ? aadsModule!.outputs.domainName : ''
output galleryId string = galleryModule.outputs.galleryId
output galleryName string = galleryModule.outputs.galleryName
