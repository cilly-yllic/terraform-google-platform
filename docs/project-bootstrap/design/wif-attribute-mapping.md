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

```text
https://app.terraform.io
```

Terraform Cloud / HCP Terraform を前提に固定値として扱う。必要になった場合のみ変数化する。

---

## 関連ドキュメント

- [docs/bootstrap.md](../bootstrap.md) — bootstrap script の実行手順
- [scripts/README.md](../../scripts/README.md) — CLI オプションと環境変数リファレンス
- [docs/design/iam-policy.md](./iam-policy.md) — IAM role 付与の設計根拠
