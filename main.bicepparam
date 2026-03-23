// ============================================================
// main.bicepparam
// Parameter overrides for Production deployment
// Usage: az deployment sub create -f main.bicep -p main.bicepparam
// ============================================================

using './main.bicep'

// ── General ───────────────────────────────────────────────────
param location            = 'japaneast'
param environmentPrefix   = 'demo'
param projectName         = 'tisogai'

// ── Networking ───────────────────────────────────────────────
param vnetAddressPrefix   = '10.10.0.0/16'
param avdSubnetPrefix     = '10.10.2.0/24'   // AVD セッションホスト
param aadsSubnetPrefix    = '10.10.3.0/24'   // Entra Domain Services (dedicated)
param storageSubnetPrefix = '10.10.4.0/24'   // Azure Files private endpoint

// ── Entra Domain Services ─────────────────────────────────────
param aadsDomainName      = 'tisogai.local'  // ← Update to your domain
param aadsSku             = 'Standard'            // Standard | Enterprise | Premium

// ── Azure Files ───────────────────────────────────────────────
param fileShareName       = 'profiles'
param fileShareQuotaGb    = 512
param storageSkuName      = 'Standard_LRS'          // Use Premium_LRS for high-IOPS workloads

// ── Tags ──────────────────────────────────────────────────────
param tags = {
  environment: 'demo'
  project: 'tisogai'
  owner: 'tisogai'
  costCenter: 'Japan-Team'
  managedBy: 'Bicep'
}
