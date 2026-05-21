# Nerdio Manager for Enterprise – Bicep Infrastructure

Deploys all foundational Azure resources required before installing Nerdio Manager for Enterprise.

## Resource inventory

| Module | Resources created |
|---|---|
| `main.bicep` | Resource Group × 2（共有インフラ用・Nerdio Manager アプリ用） |
| `modules/network.bicep` | VNet、サブネット × 3、NSG × 3 |
| `modules/entra-ds.bicep` | Entra Domain Services managed domain |
| `modules/vnet-dns.bicep` | VNet カスタム DNS 更新（AADDS DC IP を自動設定） |
| `modules/azure-files.bicep` | Storage Account, File Service, SMB Share, Private Endpoint, Private DNS Zone |

## Network layout

```
10.10.0.0/16  – vnet-prod-nerdio
 ├─ 10.10.2.0/24  snet-avd      – AVD Host Pool session hosts
 ├─ 10.10.3.0/24  snet-aadds    – Entra Domain Services (dedicated, no delegations)
 └─ 10.10.4.0/24  snet-storage  – Azure Files private endpoint
```

> **Note:** Nerdio Manager アプリコンポーネント用のサブネット（`snet-nerdio`）は Nerdio Manager 用リソースグループ（`rg-prod-nerdio-app`）内に作成する必要があるため、このテンプレートには含まれていません。Nerdio Manager のインストールウィザードで別途作成してください。

## Prerequisites

1. **Azure CLI** ≥ 2.55 or **Azure PowerShell** ≥ 11.0  
2. **Bicep CLI** ≥ 0.25 (`az bicep install`)  
3. Subscription-level **Owner** or **Contributor + User Access Administrator** role  
4. The **Microsoft.AAD** resource provider registered:
   ```bash
   az provider register --namespace Microsoft.AAD
   ```

## Deploy

### 1. Edit parameters
Open `main.bicepparam` and set your values:
- `aadsDomainName` – your AADDS DNS domain (cannot be changed after deployment)
- `location` – target Azure region
- `environmentPrefix`, `projectName` – used in all resource names

### 2. Run deployment

**Azure CLI**
```bash
az deployment sub create \
  --location japaneast \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name nerdio-infra-$(date +%Y%m%d%H%M)
```

**Azure PowerShell**
```powershell
New-AzSubscriptionDeployment `
  -Location japaneast `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.bicepparam `
  -Name "nerdio-infra-$(Get-Date -Format yyyyMMddHHmm)"
```

### 3. Preview changes first (What-If)
```bash
az deployment sub what-if \
  --location japaneast \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Post-deployment steps

### Entra Domain Services
1. **Enable password hash sync** – In Entra ID (Azure AD), enable SSPR or prompt users to change their password so Kerberos/NTLM hashes are synchronised to AADDS. Cloud-only users must reset their password once.
2. **DNS update** – `modules/vnet-dns.bicep` が AADDS プロビジョニング完了後に自動的に VNet の DNS サーバーを DC の IP に更新します。デプロイ完了後に以下のコマンドで確認してください：
   ```bash
   az network vnet show \
     --resource-group rg-prod-nerdio \
     --name vnet-prod-nerdio \
     --query "dhcpOptions.dnsServers" \
     --output tsv
   # → AADDS の DC IP アドレス（例: 10.10.3.4, 10.10.3.5）が表示されればOK
   ```

### Azure Files – AADDS 認証の有効化

デプロイ後に以下のコマンドで Entra DS 認証を有効化します：

```bash
az storage account update \
  --name <storageAccountName> \
  --resource-group rg-prod-nerdio \
  --enable-files-aadds true

# 有効化を確認
az storage account show \
  --name <storageAccountName> \
  --resource-group rg-prod-nerdio \
  --query "azureFilesIdentityBasedAuthentication" \
  --output json
# → "directoryServiceOptions": "AADDS" であればOK
```

### Azure Files – Share-level permissions（必須）

Azure Files のアクセス制御は Share-level と NTFS の2層構造です。**両方の設定が必要**です。

```
① Share-level permissions  （RBAC / ファイル共有レベル）
        ↓ 通過できたら
② NTFS permissions         （ファイル・フォルダレベル）
```

**推奨ロール割り当て：**

| 対象 | ロール | 理由 |
|---|---|---|
| AVD ユーザーグループ | `記憶域ファイル データ SMB 共有の共同作成者` | プロファイルの読み書きに必要 |
| 管理者 / Nerdio | `記憶域ファイル データ SMB 共有の特権共同作成者` | NTFS権限の変更操作が必要な場合のみ（任意） |

> **Note:** FSLogix プロファイルの通常利用には `SMB Share Contributor` のみで十分です。`Elevated Contributor` は管理者が `icacls` 等でNTFS権限を操作する場合にのみ必要です。

```bash
# スコープ文字列を変数に格納
SCOPE="/subscriptions/<サブスクリプションID>/resourceGroups/rg-prod-nerdio\
/providers/Microsoft.Storage/storageAccounts/<storageAccountName>\
/fileServices/default/fileshares/profiles"

# AVD ユーザーグループへの権限付与（必須）
az role assignment create \
  --role "Storage File Data SMB Share Contributor" \
  --assignee-object-id <AVDユーザーグループのオブジェクトID> \
  --scope "$SCOPE"

# 管理者への権限付与（NTFS権限操作が必要な場合のみ）
az role assignment create \
  --role "Storage File Data SMB Share Elevated Contributor" \
  --assignee-object-id <管理者のオブジェクトID> \
  --scope "$SCOPE"
```

### Nerdio Manager installation
After the above is complete, follow the [Nerdio Manager for Enterprise deployment guide](https://nmmhelp.getnerdio.com/) using:
- The **Nerdio Manager 用リソースグループ** (`rg-prod-nerdio-app`) をインストール先に指定
- Nerdio Manager アプリ用サブネットはインストールウィザード内で `rg-prod-nerdio-app` 内に作成
- The **AVD subnet** (`snet-avd`) as the default host pool network
- The **file share UNC path**: `\\<storageAccountName>.file.core.windows.net\profiles`

## Customisation notes

| Scenario | Change |
|---|---|
| High-IOPS profiles (>many concurrent users) | Set `storageSkuName = 'Premium_LRS'` |
| Multi-region AADDS replica | Add entries to `replicaSets[]` in `entra-ds.bicep` |
| Existing VNet | Remove the network module and pass existing subnet IDs directly |
| LDAPS | Set `enableLdaps = true` and upload PFX post-deploy |
| Filtered sync (cloud-only) | Set `syncType = 'CloudOnly'` in `entra-ds.bicep` |
