# WIF Attribute Mapping

bootstrap script が作成する Workload Identity Provider の Attribute Mapping / Attribute Condition の詳細。

---

## Attribute Mapping

| Google attribute | OIDC assertion / 導出 | 用途 |
|-----------------|----------------|------|
| `google.subject` | `assertion.sub` | 主体識別子 |
| `attribute.terraform_organization` | `assertion.terraform_organization_name` | TFC Organization 名での制限 |
| `attribute.terraform_project` | `assertion.terraform_project_name` | TFC Project 名での制限 (将来用) |
| `attribute.terraform_workspace` | `assertion.terraform_workspace_name` | Workspace 単位の impersonation 制限 (per-env SA 用) |
| `attribute.terraform_run_phase` | `assertion.terraform_run_phase` | Run phase の識別 (将来用) |
| `attribute.terraform_workspace_kind` | `workspace 名が ${FACTORY_WORKSPACE_PREFIX} で始まれば "factory" / それ以外 "service"` | Factory SA を factory workspace に限定する派生属性 |

### 派生属性 `terraform_workspace_kind`

workspace 名から CEL で導出する:

```text
attribute.terraform_workspace_kind =
  assertion.terraform_workspace_name.startsWith("${FACTORY_WORKSPACE_PREFIX}") ? "factory" : "service"
```

- `project-factory-shop` → `factory`
- `shop-prd-001` / 実験用 workspace → `service`

Factory SA (`terraform-project-factory`、org/folder の project 作成・IAM 権限を持つ強権 SA) の `workloadIdentityUser` binding をこの属性で `factory` に限定することで、**TFC org 内の任意 workspace からの成り代わり**を防ぐ。`${FACTORY_WORKSPACE_PREFIX}` の default は `project-factory-` で、`dispatch-project-bootstrap` action の workspace 名と一致する。consumer が命名を変える場合は bootstrap の `.env` で `FACTORY_WORKSPACE_PREFIX` を上書きする。

> per-env SA 側は `attribute.terraform_workspace` で個別 workspace (`{service}-{env}`) に限定済みなので、この派生属性は Factory SA の binding にのみ使う。

---

## Attribute Condition

```text
assertion.terraform_organization_name == "{TFC_ORGANIZATION_NAME}"
```

Provider 段階 (token 発行の入口) では **Organization 単位**でのみ制限する。これは外側のゲート。

その内側で、SA ごとの `workloadIdentityUser` binding が **どの workspace から impersonate 可能か**を制御する二層構造:

| SA | binding の attribute | 許可される workspace |
|----|----------------------|----------------------|
| Factory SA (`terraform-project-factory`) | `attribute.terraform_workspace_kind/factory` | `project-factory-*` (factory workspace) のみ |
| per-env SA (`terraform-{service}-{env}`) | `attribute.terraform_workspace/{service}-{env}` | その env の firebase workspace のみ |

理由:

- Provider の attribute-condition は「自 org のトークンか」を保証する floor
- 「誰が *どの* SA を使えるか」は SA binding 側で絞る方が、強権 SA (Factory) と最小権限 SA (per-env) で別々のスコープを与えられて柔軟
- bootstrap 時点では個別 workspace の存在を前提にしないが、`terraform_workspace_kind` は workspace 名の prefix から導出するため、将来作られる factory workspace も自動的にカバーされる (binding の追加メンテ不要)

---

## `attribute.terraform_workspace` の利用

本モジュールの WIF binding では `attribute.terraform_workspace` を使用する。

> **注意:** 一般的な TFC ドキュメントでは `attribute.terraform_workspace_name` が使われることがあるが、本モジュールは `attribute.terraform_workspace` を使用している。Bootstrap の Workload Identity Provider の attribute mapping がこの名前と一致している必要がある。

principal の例:

```text
principalSet://iam.googleapis.com/projects/{project_number}/locations/global/workloadIdentityPools/{pool}/attribute.terraform_workspace/{workspace_name}
```

---

## Workload Identity Provider 設定

### Issuer

```text
https://app.terraform.io
```

### Allowed Audience

**設定しない** (GCP default = provider full resource URI を採用)。

```text
//iam.googleapis.com/projects/{project_number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}
```

TFC は `TFC_GCP_PROVIDER_AUDIENCE` 未設定時に `TFC_GCP_WORKLOAD_PROVIDER_NAME` から同じ URI を default で組み立てるので、両者が default で一致する。

#### なぜ default に揃えるか

- audience が **provider 単位で unique**: 別 GCP project の WIF provider に token を replay されない (cross-audience replay attack 防止)
- Action 側で `TFC_GCP_PROVIDER_AUDIENCE` 等の env var を明示 set する必要がなくなる (= 設定漏れによる `400 invalid_grant` を構造的に防げる)

過去は `https://app.terraform.io` を allowed-audience に固定していたが、TFC 共通の generic 値で provider unique 性が無く、Action 側 env var の set 漏れで audience mismatch が起きていたため廃止した。

---

## 関連ドキュメント

- [docs/bootstrap.md](../bootstrap.md) — bootstrap script の実行手順
- [scripts/README.md](../../scripts/README.md) — CLI オプションと環境変数リファレンス
- [docs/design/iam-policy.md](./iam-policy.md) — IAM role 付与の設計根拠
