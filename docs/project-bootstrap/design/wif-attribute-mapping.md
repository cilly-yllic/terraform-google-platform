# WIF Attribute Mapping

bootstrap script が作成する Workload Identity Provider の Attribute Mapping / Attribute Condition の詳細。

---

## Attribute Mapping

| Google attribute | OIDC assertion | 用途 |
|-----------------|----------------|------|
| `google.subject` | `assertion.sub` | 主体識別子 |
| `attribute.terraform_organization` | `assertion.terraform_organization_name` | TFC Organization 名での制限 |
| `attribute.terraform_project` | `assertion.terraform_project_name` | TFC Project 名での制限 (将来用) |
| `attribute.terraform_workspace` | `assertion.terraform_workspace_name` | Workspace 単位の impersonation 制限 |
| `attribute.terraform_run_phase` | `assertion.terraform_run_phase` | Run phase の識別 (将来用) |

---

## Attribute Condition

```text
assertion.terraform_organization_name == "{TFC_ORGANIZATION_NAME}"
```

bootstrap 段階では Organization 単位でのみ制限する。Workspace 単位の制限は設けない。

理由:

- Workspace 作成は後続工程の責務
- bootstrap 時点では Workspace の存在を前提にしない
- Service Account impersonation 側 (Workspace 単位の `workloadIdentityUser` binding) でアクセス制御を追加できる

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
