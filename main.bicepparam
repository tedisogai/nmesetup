// ============================================================
// main.bicepparam
// Parameter template - 環境ごとに値をコピーしてカスタマイズしてください
// Usage: az deployment sub create -f main.bicep -p main.bicepparam
// ============================================================

using './main.bicep'

// ── General ───────────────────────────────────────────────────
param location            = 'japaneast'
param environmentPrefix   = 'prod'                  // ← 環境ごとに変更（例: prod, dev, uat）
param projectName         = 'nerdio'                // ← プロジェクト/テナント名に変更

// ── Networking ───────────────────────────────────────────────
param vnetAddressPrefix   = '10.10.0.0/16'
param avdSubnetPrefix     = '10.10.2.0/24'   // AVD セッションホスト
param aadsSubnetPrefix    = '10.10.3.0/24'   // Entra Domain Services (dedicated)
param storageSubnetPrefix = '10.10.4.0/24'   // Azure Files private endpoint

// ── Entra Domain Services ─────────────────────────────────────
param deployEntraDs       = true                    // false にすると AADDS を作成しない
param aadsDomainName      = 'aadds.contoso.local'   // ← 自社のドメイン名に変更（デプロイ後の変更不可）
param aadsSku             = 'Enterprise'            // Standard | Enterprise | Premium

// ── Azure Compute Gallery ─────────────────────────────────────
param galleryName         = ''                      // 空文字の場合は自動生成 (gal_<environmentPrefix>_<projectName>)

// ── Azure Files ───────────────────────────────────────────────
param fileShareName       = 'profiles'
param fileShareQuotaGb    = 512
param storageSkuName      = 'Standard_LRS'          // Use Premium_LRS for high-IOPS workloads

// ── Tags ──────────────────────────────────────────────────────
param tags = {
  environment: 'prod'                               // ← environmentPrefix と合わせる
  project: 'nerdio'                                  // ← projectName と合わせる
  owner: 'changeme'
  costCenter: 'changeme'
  managedBy: 'Bicep'
}
