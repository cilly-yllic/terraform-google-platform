# dispatch-tfc-project-bootstrap

`settings.yml` を元に Terraform Cloud の `project-factory-{service}` Workspace へ Run を起動する GitHub Action。1 サービス = 1 ワークスペースで、`environments` map を `for_each` 展開することで複数 env を 1 Run でまとめて bootstrap する。

## Usage

### 単一 env を指定する場合（matrix 互換）

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  with:
    service: my-service
    environment: prd-001
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    parent_organization_id: "999999999999"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

### labels で複数 env を 1 Run にまとめる場合

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  with:
    service: my-service
    # environment 未指定 → settings.environments 全件が候補
    labels: '["^tier:dev$"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    parent_organization_id: "999999999999"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

`environment` と `labels` の **少なくとも一方**は必須。両方未指定の場合は error 終了する。

## Inputs

| Name | Required | Default | Description |
|------|:--------:|---------|-------------|
| `service` | yes | — | Service name |
| `environment` | no | `""` | 対象 env キー (`prd-001` 等)。未指定なら `settings.environments` 全件が候補に。`labels` と AND 評価される |
| `settings_path` | no | `terraform/settings.yml` | Path to settings.yml in the calling repo |
| `tfc_org` | yes | — | Terraform Cloud organization name |
| `tfc_workspace_name` | no | `project-factory-{service}` | Workspace name pattern (placeholders: `{service}`) |
| `parent_organization_id` | no | — | GCP Org ID。project 配置先の fallback (settings.yml `folder_id` 未指定時) |
| `parent_folder_id` | no | — | GCP Folder ID。project 配置先の fallback (settings.yml `folder_id` 未指定時) |
| `bootstrap_project_id` | no | `infra-bootstrap` | Bootstrap project ID |
| `bootstrap_project_number` | yes | — | Bootstrap project number (numeric, for WIF resource name) |
| `workload_identity_pool_id` | no | `terraform-cloud` | WIF Pool ID |
| `workload_identity_provider_id` | no | `terraform-cloud` | WIF Provider ID |
| `tfc_token` | yes | — | Terraform Cloud API token |
| `enable_webhook_notification` | no | `false` | Create TFC notification for Phase 2 webhook |
| `cloud_run_webhook_url` | no | — | Cloud Run router URL (required if webhook enabled) |
| `cloud_run_webhook_secret` | no | — | HMAC secret for webhook |
| `module_version` | no | — | Registry module の version 制約 (`0.0.0-rc16` や `~> 1.0`)。空なら Action が Terraform Registry を query して **最新版 (pre-release 含む) を auto-resolve** し main.tf に書き込む。Terraform は version 制約なしだと pre-release を選択しない仕様なので、`0.0.0-rcN` しか publish されていない間は空でも壊れない fallback として動く |
| `labels` | no | `""` | JS RegExp パターンの JSON 配列 (`'["^tier:dev$","^region:apne1$"]'`)。各 env の `labels` が全パターンに一致 (AND) しないと対象から外れる。詳細: [Environment gating](#environment-gating) |

## Outputs

| Name | Description |
|------|-------------|
| `run_id` | Terraform Cloud Run ID (skipped 時は空) |
| `run_url` | URL to the Run in TFC UI (skipped 時は空) |
| `workspace_id` | Workspace ID (skipped 時は空) |
| `workspace_name` | Workspace name (skipped 時は空) |
| `applied_envs` | JSON 配列。今回 Run で更新された env キー (e.g. `["prd-001","dev-002"]`) |
| `state_removed_envs` | JSON 配列。`removed { destroy = false }` で state からだけ外された env キー (`retained_envs` で守られた env が `environments:` から消えた場合) |
| `destroyed_envs` | JSON 配列。Terraform に destroy された env キー (`environments:` からも `retained_envs:` からも消えた env) |
| `filtered_envs` | JSON 配列。`status: inactive` や labels 不一致で対象から外された env と理由 (`[{env, reason, detail}]`) |
| `skipped` | `"true"` if no Run was created (env 変化なし)、`"false"` otherwise |
| `skip_reason` | `skipped=true` 時の理由コード: `no_changes` (それ以外は空) |

## settings.yml 構造

```yaml
service: my-service

# 削除されても Terraform destroy させたくない env のリスト。
# environments: から消えた env が retained_envs にあれば
# `removed { destroy = false }` で state からだけ外し、GCP リソースは残す。
retained_envs:
  - prd-001

environments:
  prd-001:
    status: active
    labels:
      - tier:prd
      - region:apne1
    billing_account_id: "AAAA-AAAA-AAAA"
  dev-001:
    # status 省略時は active、labels 省略時は []
    labels:
      - tier:dev
      - region:apne1
    billing_account_id: "BBBB-BBBB-BBBB"
```

完全なサンプル: [`examples/settings.yml`](../../examples/settings.yml)

## Environment gating

各 env を Run 対象に含めるかを以下の 2 段で判定:

| Gate | 条件 | 挙動 |
|------|------|------|
| `status` | `environments.<env>.status: inactive` だと **常に**対象外。設定だけ先行管理してインフラはまだ立てたくない env で使う (省略時は `active`) | `filtered_envs` に `reason: status_inactive` で記録 |
| `labels` (AND) | Action input `labels` が JSON 配列の RegExp で、各パターンが env の `labels` のいずれかにマッチする必要あり。input が空ならゲート無効 | `filtered_envs` に `reason: labels_mismatch` で記録 |

`environment` 指定時はその env だけが gate を通り、未指定時は `settings.environments` 全件が候補となる。

> **Tips**: パターンは `RegExp.test()` で評価され、デフォルトは部分一致。完全一致したい場合は `^...$` で囲む。

## ケース挙動表（`environments` ⇄ `retained_envs` ⇄ 前回 map）

| `environments` | `retained_envs` | 前回 map | 挙動 |
|:---:|:---:|:---:|---|
| ✅ | ❌ | — | 通常運用（status/labels で更新 or filtered） |
| ✅ | ✅ | — | 通常運用（誤削除に対する安全網として `retained_envs` が dormant 待機） |
| ❌ | ✅ | ✅ | **state からだけ外す**（`removed { destroy = false }` 生成、GCP は残る） |
| ❌ | ✅ | ❌ | no-op |
| ❌ | ❌ | ✅ | **destroy**（`environments` map から消えて Terraform が `for_each` 差分で destroy） |
| ❌ | ❌ | ❌ | no-op |

## Notes

- main.tf / versions.tf は Action 内に同梱されたテンプレートを毎回 Terraform Cloud Configuration Version として upload します。Workspace 側に手動で VCS 連携や config を用意する必要はありません。
- `state_removed_envs` が非空の場合、main.tf に `removed { lifecycle { destroy = false } }` ブロックを動的生成して同梱します（Terraform 1.7+ が必須、`versions.tf` の `required_version` は `>= 1.7`）。
- `parent` と `environments` は JSON 文字列 (`hcl: false`) として TFC Variable に格納されます。消費側の Terraform では `jsondecode()` で展開してください。
- `TFC_GCP_WORKLOAD_PROVIDER_NAME` には `bootstrap_project_number` (numeric) を使用します。GCP WIF リソース名は project number を要求するため、project ID ではなく project number を指定してください。
- `terraform-${service}-${environment}` の長さが 30 字を超える env が含まれていると error で停止します（GCP SA ID の制限）。
