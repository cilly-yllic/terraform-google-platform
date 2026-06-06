# modules/secret-manager

Placeholder submodule for enabling the Secret Manager API.

<details><summary>Ja</summary>

Secret Manager API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. The `main.tf` is empty — the submodule exists solely as an attach point for future resource management.

<details><summary>Ja</summary>

なし。実 main.tf は API 有効化のための拡張ポイントとしてのみ存在し、現状は空。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |

## Outputs

| Name | Description |
|------|-------------|
| `enabled` | Always `true` (Secret Manager is enabled whenever this submodule is invoked) |

## Related APIs

- `secretmanager.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.secret_manager != null`.

## Design intent

Secrets themselves (`google_secret_manager_secret`) are intentionally **not** created by this module. The lifecycle of confidential values is expected to be managed in separate Terraform stacks, via the Secret Manager CLI, or via Console.

This submodule is kept as an anchor for future expansion (e.g. if managing secrets / IAM bindings via this module becomes desirable).

<details><summary>Ja</summary>

Secret (`google_secret_manager_secret`) 自体は本モジュールでは作成しない。秘匿情報のライフサイクルは個別の Terraform stack / Secret Manager CLI / Console で管理する想定。

将来 Secret 自体や IAM binding を本モジュール経由で管理したくなった場合に拡張する拠点として残している。

</details>
