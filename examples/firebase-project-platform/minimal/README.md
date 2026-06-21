# examples/minimal

Minimal configuration with Firebase enable + Firestore only.

<details><summary>Ja</summary>

Firebase 化 + Firestore のみの最小構成。

</details>

## What this example shows

- The default configuration achieved by passing feature variables as **`true`**
- The only required input is `project_id`
- API enablement is auto-derived from feature on/off
- `region` defaults to `asia-northeast1`

<details><summary>Ja</summary>

- 機能変数を **`true`** で渡すだけのデフォルト構成
- 必須引数は `project_id` のみ
- API 有効化は機能 on/off から自動判定される
- `region` は `asia-northeast1`

</details>

## Resources you can expect to be created

| Category | Resource |
|----------|----------|
| API enablement | `cloudresourcemanager`, `serviceusage`, `firebase`, `firestore`, `firebaserules` |
| Firebase | `google_firebase_project.this` |
| Firestore | Default database (`(default)`, location = `asia-northeast1`, type = `FIRESTORE_NATIVE`) + deny-all ruleset |
| IAM | None (`users` / `ci_service_account` / `service_accounts` not specified) |

## How to use

### Prerequisites

- The GCP Project (`my-minimal-project`) is **already created** (e.g. by the upstream project-factory stage)
- Google credentials are configured (via `gcloud auth application-default login` or similar)

<details><summary>Ja</summary>

- GCP Project (`my-minimal-project`) が **既に作成済み** であること (上流の project-factory ステージなどで作成)
- `gcloud auth application-default login` などで Google credentials が設定されていること

</details>

### Run

```bash
cd examples/firebase-project-platform/minimal

# Rewrite project_id with your real value, or pass via -var
terraform init
terraform plan  -var "project_id=<YOUR_PROJECT_ID>"
terraform apply -var "project_id=<YOUR_PROJECT_ID>"
```

> `main.tf` hard-codes `project_id = "my-minimal-project"`. In real use, either edit that line or convert to a `variable "project_id"` and pass it via `-var` as above.

<details><summary>Ja</summary>

`main.tf` 内では `project_id = "my-minimal-project"` がハードコードされている。実利用時はそこを書き換えるか、`variable "project_id"` を定義して上記の `-var` で渡す形に変更する。

</details>

### Tear down

```bash
terraform destroy -var "project_id=<YOUR_PROJECT_ID>"
```

> The Firestore database is created with `delete_protection_state = "DELETE_PROTECTION_DISABLED"`, so `destroy` will remove it. For production, consider `delete_protection_state = "DELETE_PROTECTION_ENABLED"`.

<details><summary>Ja</summary>

Firestore database は `delete_protection_state = "DELETE_PROTECTION_DISABLED"` で作成されるため、`destroy` で消える。本番では `delete_protection_state = "DELETE_PROTECTION_ENABLED"` を検討する。

</details>

## Next steps

- To add more features → see [`examples/full/`](../full/) for `storage`, `hosting`, `authentication`, etc.
- For custom settings → specify each feature variable as an object ([docs/variables-reference.md](../../docs/variables-reference.md))

<details><summary>Ja</summary>

- 機能を追加したい → [`examples/full/`](../full/) を参考に `storage`, `hosting`, `authentication` 等を追加
- カスタム設定にしたい → 各機能変数を object 形式で指定 ([docs/variables-reference.md](../../docs/variables-reference.md))

</details>
