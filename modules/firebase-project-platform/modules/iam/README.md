# modules/iam

Submodule that manages Project-level IAM (users / CI SA / additional SAs) in one place.

<details><summary>Ja</summary>

Project レベル IAM (ユーザー / CI SA / 追加 SA) を一括で管理する submodule。

</details>

## Resources created

| Resource | Role |
|----------|------|
| `google_project_iam_member.user` | Grants roles to users in `users[]` (base role + optional deploy roles) |
| `google_service_account.ci` | Created when `ci_service_account != null` |
| `google_project_iam_member.ci_role` | Grants roles to the CI SA (auto-derived + `additional_roles`) |
| `google_service_account_iam_member.ci_wif` | (optional) Grants `roles/iam.workloadIdentityUser` to attribute-based principalSet members on the CI SA |
| `google_service_account.this` | Creates each SA in `service_accounts[]` via for_each |
| `google_project_iam_member.service_account_role` | Grants roles to each SA (computed from `args` for `type = "deploy"`, plus explicit `roles`) |
| `google_service_account_iam_member.sa_wif` | (optional) Grants `roles/iam.workloadIdentityUser` to attribute-based principalSet members on a manual SA that sets `wif` |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `users` | `list(object)` | `[]` | `email`, `role` (`viewer\|editor\|owner`), `deploy` (bool) |
| `ci_service_account` | `object \| null` | `null` | `account_id`, `display_name`, `roles` (already-computed roles list), `wif` (optional `{ pool_resource_name, principals[{attribute, value}] }`) |
| `service_accounts` | `list(object)` | `[]` | `account_id`, `display_name`, `type`, `roles`, `args`, `wif` (optional, same shape as `ci_service_account.wif` — keyless impersonation from external CI for read-only SAs) |

The root module receives `var.users` / `var.ci_service_account` / `var.service_accounts`, performs preprocessing (e.g. CI SA role auto-derivation), and passes the result to this submodule.

<details><summary>Ja</summary>

ルートモジュールが `var.users` / `var.ci_service_account` / `var.service_accounts` を受け取り、必要な前処理 (CI SA の roles 自動計算など) を行った上で本 submodule に渡している。

</details>

## Outputs

| Name | Description |
|------|-------------|
| `user_members` | List of granted IAM members |
| `user_roles` | List of granted roles |
| `ci_service_account_email` | CI SA email (`null` if not created) |
| `ci_service_account_wif_members` | List of WIF principalSet members bound to the CI SA (`[]` when `wif` is not configured) |
| `ci_service_account_roles` | Roles granted to the CI SA |
| `service_account_emails` | `{ account_id => email }` |
| `service_account_ids` | `{ account_id => unique_id }` |
| `service_account_roles` | `{ account_id => [roles...] }` (auto-computed + explicit, combined) |
| `service_account_wif_members` | `{ binding_id => member }` WIF principalSet members bound to manual SAs (`{}` when none set `wif`) |

## User role grant logic

```
viewer  → roles/viewer
editor  → roles/editor
owner   → roles/owner

If deploy=true, additionally:
  roles/cloudfunctions.admin
  roles/artifactregistry.reader
```

## Auto-derived roles for CI / additional SAs

See [docs/service-accounts.md](../../docs/service-accounts.md).

## Related APIs

- `iam.googleapis.com` (auto-enabled by the root module when SAs are created)
