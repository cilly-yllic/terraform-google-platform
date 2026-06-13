# Architecture

Describes where this repository (`terraform-google-firebase-project-platform`) sits, and how it splits responsibility with the bundled reference implementations.

<details><summary>Ja</summary>

本リポジトリ (`terraform-google-firebase-project-platform`) の位置づけと、同梱する reference 実装との責務分離を説明する。

</details>

---

## Position of this repository

The **Terraform execution platform** that provisions a GCP / Firebase Project and the **shared Module called by that platform** are different layers. This repository owns the latter.

```text
+--- Terraform execution platform (caller-side repos) -------------+
|                                                                  |
|   infra-bootstrap          : Workload Identity Federation, etc.   |
|   project-factory          : Creates GCP Project / Billing / IAM  |
|   {service}-dev / stg / prd: Per-service workspaces               |
|                                                                  |
+------------------------------------------------------------------+
                          ↓ module source = registry
+--- This repository (public Terraform Module) --------------------+
|                                                                  |
|   terraform-google-firebase-project-platform                     |
|     - Manages only resources / APIs / IAM inside the Project     |
|     - Feature variables (null / true / object) for on/off        |
|                                                                  |
+------------------------------------------------------------------+
```

- **This module does not create the Project itself.** `project_id` is an input; the module only manages resources / API enablement / IAM **inside** an existing Project.
- The upstream **project-factory stage** is expected to have created the Project, attached billing, and provisioned the initial SAs.
- Each service-side Workspace references this module via `source = "cilly-yllic/platform/google//modules/firebase-project-platform"`.

<details><summary>Ja</summary>

GCP / Firebase Project を **構築する Terraform 実行基盤** と、**それらの基盤から呼び出される共通 Module** は別レイヤーであり、本リポジトリは後者にあたる。

- **本モジュールは Project そのものを作らない**。`project_id` は引数として受け取り、Project 内部のリソース・API 有効化・IAM のみ管理する
- 上流の **project-factory ステージ** で Project / Billing 紐付け / 初期 SA を作成しておく前提
- 各サービス側 Workspace は本モジュールを `source = "cilly-yllic/platform/google//modules/firebase-project-platform"` で参照して利用する

</details>

---

## Layer separation principles

| Layer | Responsibility | Handled in this repo |
|-------|----------------|----------------------|
| Bootstrap | WIF / shared GCP Project for running Terraform | × (separate repo) |
| project-factory | GCP Project creation / billing / initial IAM | × (separate repo) |
| **firebase-project-platform** | APIs / Firebase / IAM **inside** the Project | **○ (this module)** |
| Service Workspace config | Feeding values into this module | × (caller side) |

Each layer is expected to use a separate Service Account and state file. This module limits its responsibility to "inside the Project" to avoid interfering with other layers.

<details><summary>Ja</summary>

レイヤーごとに **使う Service Account** と **state file** を分離する想定であり、本モジュールは「Project 内部のみ」に責務を絞ることで他レイヤーへの干渉を防ぐ。

</details>

---

## Bundled reference implementations

In addition to the public Terraform Module itself, two implementations are bundled to handle the Terraform Cloud (TFC) handoff. **Both are optional** — the Module can be used standalone.

```
.
├── (Terraform Module proper: main.tf / modules/)
│
├── cloud-run-router/   # Cloud Run service: TFC notification → repository_dispatch
└── actions/dispatch/   # GitHub Action: {service}-{env} workspace upsert + Run dispatch
```

### cloud-run-router

- **Input**: A Run completion notification from TFC (`POST /webhook`, HMAC-SHA512 signed).
- **Output**: A GitHub `repository_dispatch` (the `firebase_platform_requested` event to the Project Repository).
- **Goal**: Detect project-factory Run completion and trigger the subsequent firebase-platform Run — the core of the Phase 2 (webhook-driven) architecture.
- Details: [cloud-run-router/README.md](../cloud-run-router/README.md)

### actions/dispatch

- **Input**: The caller repo's `settings.yml` (`firebase_platform` section) + `service` / `environment`.
- **Output**: An upsert of the TFC `{service}-{environment}` workspace + a Run start.
- **Goal**: Reference project-factory outputs (project_id, etc.), inject feature variables as Terraform variables, and create the Run.
- Details: [actions/dispatch/README.md](../actions/dispatch/README.md)

<details><summary>Ja</summary>

公開 Terraform Module 本体に加えて、Terraform Cloud (TFC) との handoff を担う実装を 2 種類同梱している。**いずれも利用は任意** で、Module 単独で利用してもよい。

### cloud-run-router

- **入力**: TFC からの Run completion notification (`POST /webhook`, HMAC-SHA512 署名付き)
- **出力**: GitHub `repository_dispatch` (Project Repository に対して `firebase_platform_requested` event)
- **目的**: project-factory の Run 完了を検知して、続く firebase-platform の Run を発火する Phase 2 (webhook-driven) アーキテクチャの中核
- 詳細: [cloud-run-router/README.md](../cloud-run-router/README.md)

### actions/dispatch

- **入力**: 利用側リポジトリの `settings.yml` (`firebase_platform` セクション) + `service` / `environment`
- **出力**: TFC `{service}-{environment}` workspace の upsert + Run 起動
- **目的**: project-factory の outputs (project_id 等) を参照し、機能変数を Terraform 変数として注入して Run を作る
- 詳細: [actions/dispatch/README.md](../actions/dispatch/README.md)

</details>

---

## Handoff flow (Phase 2 webhook-driven)

```text
project-factory workspace (TFC)
  ↓ Run applied
  ↓ TFC notification (HTTP POST, HMAC-SHA512)
cloud-run-router (Cloud Run, bundled in this repo)
  ↓ HMAC verify → workspace_name routing → (service, env, source_repo) parse
  ↓ GitHub repository_dispatch (event_type = firebase_platform_requested)
Caller Project Repository (GitHub Actions)
  ↓ Calls actions/dispatch
  ↓ Reads settings.yml + project-factory outputs
  ↓ Upserts {service}-{env} workspace + syncs variables
  ↓ Starts the TFC Run
{service}-{env} workspace (TFC)
  ↓ Applies module "firebase_platform" { source = "cilly-yllic/platform/google//modules/firebase-project-platform" }
Firebase / Firestore / Storage / IAM etc. are created inside the GCP Project
```

### Relationship to Phase 1 (polling)

cloud-run-router is not invoked unless a TFC notification is configured. It coexists with Phase 1 (where an orchestrator detects project-factory completion via polling and calls actions/dispatch).

| State | cloud-run-router | actions/dispatch |
|-------|------------------|------------------|
| Phase 1 only | Not deployed | Called from the orchestrator |
| Transitional | Deployed (per-service opt-in) | Called from either path |
| Phase 2 only | Deployed (all services) | Called via repository_dispatch only |

<details><summary>Ja</summary>

cloud-run-router は TFC notification が設定されていない限り呼ばれない。Phase 1 (orchestrator が polling で project-factory 完了を検知し actions/dispatch を call) と共存できる。

- Phase 1 only: cloud-run-router 未デプロイ / actions/dispatch は orchestrator から call
- 移行期: cloud-run-router デプロイ済 (service 単位 opt-in) / actions/dispatch はどちらの経路からも call
- Phase 2 only: cloud-run-router デプロイ済 (全 service) / actions/dispatch は repository_dispatch 経由のみ

</details>

---

## Submodule classification

| Category | Submodule | Resources created |
|----------|-----------|-------------------|
| Resource-creating | `firebase` | `google_firebase_project` |
| Resource-creating | `auth` | `google_identity_platform_config` |
| Resource-creating | `firestore` | `google_firestore_database`, `google_firebaserules_ruleset/release` |
| Resource-creating | `rtdb` | `google_firebase_database_instance` |
| Resource-creating | `storage` | `google_firebase_storage_bucket`, `google_storage_bucket`, `google_storage_bucket_iam_member`, `google_firebaserules_ruleset/release` |
| Resource-creating | `hosting` | `google_firebase_web_app`, `google_firebase_hosting_site` |
| Resource-creating | `app-hosting` | `google_firebase_app_hosting_backend`, `google_service_account`, `google_project_iam_member` |
| Resource-creating | `data-connect` | `google_firebase_data_connect_service`, `google_sql_database_instance`, `google_sql_database` |
| API placeholder | `fcm`, `remote-config`, `app-check`, `crashlytics`, `performance`, `analytics`, `extensions` | None (API enablement only) |
| API placeholder | `secret-manager`, `cloud-tasks`, `cloud-scheduler`, `pubsub`, `eventarc` | None (API enablement only) |
| Cross-cutting | `iam` | `google_project_iam_member`, `google_service_account` |

**API placeholder** submodules currently enable the corresponding API only. They serve as extension points for future resource management (e.g. Remote Config templates, App Check providers).

<details><summary>Ja</summary>

| 分類 | サブモジュール | 作成されるリソース |
|------|---------------|-------------------|
| リソース作成型 | `firebase` | `google_firebase_project` |
| リソース作成型 | `auth` | `google_identity_platform_config` |
| リソース作成型 | `firestore` | `google_firestore_database`, `google_firebaserules_ruleset/release` |
| リソース作成型 | `rtdb` | `google_firebase_database_instance` |
| リソース作成型 | `storage` | `google_firebase_storage_bucket`, `google_storage_bucket`, `google_storage_bucket_iam_member`, `google_firebaserules_ruleset/release` |
| リソース作成型 | `hosting` | `google_firebase_web_app`, `google_firebase_hosting_site` |
| リソース作成型 | `app-hosting` | `google_firebase_app_hosting_backend`, `google_service_account`, `google_project_iam_member` |
| リソース作成型 | `data-connect` | `google_firebase_data_connect_service`, `google_sql_database_instance`, `google_sql_database` |
| API有効化のみ | `fcm`, `remote-config`, `app-check`, `crashlytics`, `performance`, `analytics`, `extensions` | なし (API 有効化のみ) |
| API有効化のみ | `secret-manager`, `cloud-tasks`, `cloud-scheduler`, `pubsub`, `eventarc` | なし (API 有効化のみ) |
| 横断型 | `iam` | `google_project_iam_member`, `google_service_account` |

**API有効化のみ** のサブモジュールは現時点では対応 API を有効化するのみ。将来的なリソース管理 (Remote Config テンプレート、App Check プロバイダ等) の拡張ポイントとして機能する。

</details>

---

## Upstream documentation

| Upstream document | Mapping in this repo |
|---|---|
| [architecture.md](../project-bootstrap/architecture.md) | Overall architecture reference |
| [related-components.md](../project-bootstrap/related-components.md) | Related components including this repo |

Full index with descriptions: [upstream-spec-links.md](./upstream-spec-links.md).

<details><summary>Ja</summary>

| 上流ドキュメント | 本リポジトリでの対応 |
|---|---|
| [architecture.md](../project-bootstrap/architecture.md) | 全体アーキテクチャの参照元 |
| [related-components.md](../project-bootstrap/related-components.md) | 本リポジトリを含む関連コンポーネント |

詳細な説明付きインデックス: [upstream-spec-links.md](./upstream-spec-links.md)。

</details>

---

## API auto-enablement

To avoid making callers enumerate `google_project_service` individually, the module decides which APIs to enable from the feature flags.

- `firestore = true` → `firestore.googleapis.com`, `firebaserules.googleapis.com`
- `app_hosting = { ... }` → `firebaseapphosting.googleapis.com`, `run.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`
- `cloud_functions = true` → `cloudfunctions.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`

The full mapping is in [api-auto-enablement.md](./api-auto-enablement.md).

`additional_apis` extends this further (e.g. `iap.googleapis.com`).

<details><summary>Ja</summary>

利用者が `google_project_service` を個別に列挙しなくて済むよう、機能 on/off から有効化する API を自動決定する。

完全な対応表は [api-auto-enablement.md](./api-auto-enablement.md) を参照。`additional_apis` でさらに追加可能 (例: `iap.googleapis.com`)。

</details>

---

## Zero-side-effect principle

When a feature variable is `null`, **none** of the following are created:

- The submodule's resources (Firestore database, Storage bucket, IAM bindings, etc.)
- API enablement (`google_project_service`)
- Roles auto-assigned to the CI SA

If a feature is later disabled, Terraform destroys things normally (the API itself stays enabled because `disable_on_destroy = false`, but the additional resources go away).

<details><summary>Ja</summary>

機能変数を `null` にした場合、その機能に対応する submodule のリソース・API 有効化・CI SA への自動付与 role の **すべてが作成されない**。

機能を後から無効化した場合、Terraform は通常通り destroy を行う (API 自体は `disable_on_destroy = false` のため有効のまま残るが、追加リソースは消える)。

</details>

---

## State and providers

- `terraform >= 1.10.0`
- `hashicorp/google` `>= 6.0, < 8.0`
- `hashicorp/google-beta` `>= 6.0, < 8.0`

`google-beta` is used only for Firebase-related resources (`google_firebase_*`).

<details><summary>Ja</summary>

`google-beta` は Firebase 関連リソース (`google_firebase_*`) でのみ利用している。

</details>
