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

@description('DNS domain name for Entra Domain Services')
param aadsDomainName string = 'aadds.contoso.local'

@description('SKU for the Entra Domain Services managed domain (Standard or Enterprise or Premium)')
@allowed(['Standard', 'Enterprise', 'Premium'])
param aadsSku string = 'Enterprise'

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
var rgName = 'rg-${suffix}'                        // 共有インフラ用 RG（VNet / AADDS / Storage）
var nerdioRgName = 'rg-${suffix}-app'              // Nerdio Manager インストール用 RG

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

module aadsModule 'modules/entra-ds.bicep' = {
  name: 'deploy-entra-ds'
  scope: resourceGroup
  params: {
    location: location
    suffix: suffix
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

// ── Outputs ───────────────────────────────────────────────────
output resourceGroupName string = resourceGroup.name
output nerdioResourceGroupName string = nerdioResourceGroup.name
output vnetId string = networkModule.outputs.vnetId
output avdSubnetId string = networkModule.outputs.avdSubnetId
output aadsSubnetId string = networkModule.outputs.aadsSubnetId
output storageSubnetId string = networkModule.outputs.storageSubnetId
output storageAccountName string = storageModule.outputs.storageAccountName
output fileShareName string = storageModule.outputs.fileShareName
output aadsDomainName string = aadsModule.outputs.domainName
