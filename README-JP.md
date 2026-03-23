# Nerdio Manager for Enterprise – Bicep インフラストラクチャ

Nerdio Manager for Enterprise のインストールに必要な、すべての基盤 Azure リソースをデプロイします。

## リソース一覧

| モジュール | 作成されるリソース |
|---|---|
| `main.bicep` | リソースグループ × 2（共有インフラ用・Nerdio Manager アプリ用） |
| `modules/network.bicep` | VNet、サブネット × 3、NSG × 3 |
| `modules/entra-ds.bicep` | Entra Domain Services マネージドドメイン |
| `modules/azure-files.bicep` | ストレージアカウント、ファイルサービス、SMB 共有、プライベートエンドポイント、プライベート DNS ゾーン |

## ネットワーク構成

```
10.10.0.0/16  – vnet-prod-nerdio
 ├─ 10.10.2.0/24  snet-avd      – AVD ホストプールのセッションホスト
 ├─ 10.10.3.0/24  snet-aadds    – Entra Domain Services 専用（委任・サービスエンドポイント不可）
 └─ 10.10.4.0/24  snet-storage  – Azure Files プライベートエンドポイント
```

> **注意：** Nerdio Manager アプリコンポーネント用のサブネット（`snet-nerdio`）は Nerdio Manager 用リソースグループ（`rg-prod-nerdio-app`）内に作成する必要があるため、このテンプレートには含まれていません。Nerdio Manager のインストールウィザードで別途作成してください。

## 前提条件

1. **Azure CLI** ≥ 2.55 または **Azure PowerShell** ≥ 11.0
2. **Bicep CLI** ≥ 0.25（`az bicep install` でインストール）
3. サブスクリプションレベルの **所有者** または **共同作成者 + ユーザーアクセス管理者** ロール
4. **Microsoft.AAD** リソースプロバイダーの登録：
   ```bash
   az provider register --namespace Microsoft.AAD
   ```

## デプロイ手順

### 1. パラメーターの編集

`main.bicepparam` を開き、以下の値を設定します：
- `aadsDomainName` – AADDS の DNS ドメイン名（デプロイ後の変更不可）
- `location` – デプロイ先の Azure リージョン
- `environmentPrefix`、`projectName` – すべてのリソース名に使用されるプレフィックス

### 2. デプロイの実行

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

### 3. 事前に変更内容を確認する（What-If）

```bash
az deployment sub what-if \
  --location japaneast \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## デプロイ後の作業

### Entra Domain Services

1. **パスワードハッシュ同期の有効化** – Entra ID（Azure AD）で SSPR を有効化するか、ユーザーにパスワードの変更を促し、Kerberos/NTLM ハッシュを AADDS に同期させます。クラウドオンリーユーザーは一度パスワードのリセットが必要です。
2. **DNS の更新** – AADDS のプロビジョニング完了後、VNet の DNS サーバーをポータルまたはデプロイ出力 `domainControllerIpAddresses` に表示されるドメインコントローラーの IP アドレスに更新します。
3. **LDAPS（任意）** – `enableLdaps = true` を設定した場合は、デプロイ後にポータルから有効な PFX 証明書をアップロードします。

### Azure Files – ドメイン参加

ドメイン参加済みの VM 上で以下のスクリプトを実行し、ファイル共有の Kerberos 認証を有効化します：

```powershell
# AADDS ドメインに参加済みの VM 上で実行
$storageAccountName = "<output: storageAccountName>"
$resourceGroupName  = "<output: resourceGroupName>"
$storageKey         = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName `
                         -Name $storageAccountName)[0].Value

# ストレージアカウントを AADDS ドメインに参加させる
Join-AzStorageAccountForAuth `
  -ResourceGroupName $resourceGroupName `
  -Name $storageAccountName `
  -DomainAccountType 'ComputerAccount' `
  -OrganizationalUnitDistinguishedName 'OU=AADDC Computers,DC=aadds,DC=contoso,DC=local'
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

### Azure Files – 共有レベルのアクセス許可（必須）

Azure Files のアクセス制御は 共有レベル と NTFS の 2 層構造です。**両方の設定が必要**です。

```
① 共有レベルのアクセス許可  （RBAC / ファイル共有レベル）
        ↓ 通過できたら
② NTFS アクセス許可         （ファイル・フォルダレベル）
```

**推奨ロール割り当て：**

| 対象 | ロール | 理由 |
|---|---|---|
| AVD ユーザーグループ | `記憶域ファイル データ SMB 共有の共同作成者` | プロファイルの読み書きに必要 |
| 管理者 / Nerdio | `記憶域ファイル データ SMB 共有の特権共同作成者` | NTFS 権限の変更操作が必要な場合のみ（任意） |

> **注意：** FSLogix プロファイルの通常利用には `SMB 共有の共同作成者` のみで十分です。`特権共同作成者` は管理者が `icacls` 等で NTFS 権限を操作する場合にのみ必要です。

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

# 管理者への権限付与（NTFS 権限操作が必要な場合のみ）
az role assignment create \
  --role "Storage File Data SMB Share Elevated Contributor" \
  --assignee-object-id <管理者のオブジェクトID> \
  --scope "$SCOPE"
```

### Azure Files – NTFS アクセス許可

共有レベルのアクセス許可設定後、ドメイン参加済み VM 上から NTFS 権限を設定します：

```powershell
# ドメイン参加済みVM（snet-avd）上で実行
$sharePath = "\\<storageAccountName>.file.core.windows.net\profiles"

# ドライブをマウント（Kerberos 認証）
net use Z: $sharePath

# NTFS 権限を設定
# AVD ユーザー：フォルダの作成・自分のサブフォルダへのフルコントロール
icacls Z:\ /grant "<ドメイン名>\<AVDユーザーグループ>:(M)"
icacls Z:\ /grant "CREATOR OWNER:(OI)(CI)(IO)(F)"

# 管理者：フルコントロール
icacls Z:\ /grant "<ドメイン名>\Domain Admins:(F)"

# ドライブの解放
net use Z: /delete
```

### Nerdio Manager のインストール

上記の作業がすべて完了したら、[Nerdio Manager for Enterprise デプロイガイド](https://nmmhelp.getnerdio.com/) に従ってインストールを進めます。インストール時は以下の値を使用してください：

- **Nerdio Manager 用リソースグループ**（`rg-prod-nerdio-app`）をインストール先に指定
- Nerdio Manager アプリ用サブネットはインストールウィザード内で `rg-prod-nerdio-app` 内に作成
- **AVD サブネット**（`snet-avd`）をデフォルトのホストプールネットワークに使用
- **ファイル共有の UNC パス**：`\\<storageAccountName>.file.core.windows.net\profiles`

## カスタマイズ

| シナリオ | 変更内容 |
|---|---|
| 高 IOPS が必要なプロファイル（同時接続ユーザーが多い場合） | `storageSkuName = 'Premium_LRS'` に変更 |
| 複数リージョンへの AADDS レプリカ展開 | `entra-ds.bicep` の `replicaSets[]` にエントリを追加 |
| 既存の VNet を使用する場合 | ネットワークモジュールを削除し、既存のサブネット ID を直接指定 |
| LDAPS を有効化する場合 | `enableLdaps = true` を設定し、デプロイ後に PFX 証明書をアップロード |
| クラウドオンリーユーザーのみ同期する場合 | `entra-ds.bicep` の `syncType = 'CloudOnly'` に変更 |
