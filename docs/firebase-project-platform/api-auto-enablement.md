# API auto-enablement

The module derives which GCP APIs to enable from feature variable state. Callers do not need to enumerate `google_project_service` manually.

Implementation: the `locals.conditional_apis` block in [`main.tf`](../main.tf).

<details><summary>Ja</summary>

機能変数の状態から有効化する GCP API を自動決定する。利用者が `google_project_service` を個別に列挙する必要はない。

実装は [`main.tf`](../main.tf) の `locals.conditional_apis` ブロック。

</details>

---

## Design rationale

- The mapping "feature on/off ↔ required APIs" is owned by **this module**, by design.
- The caller is not given a separate `enable_api_xxx = true` flag (it would duplicate the feature on/off state).
- For APIs callers need beyond this set, use `additional_apis`.
- We run with `disable_on_destroy = false` because disabling APIs on Project destroy can break unrelated resources.
- We set `disable_dependent_services = true` to avoid leaving orphaned dependent APIs enabled.

<details><summary>Ja</summary>

- **「機能 on/off ↔ 必要な API」の対応は本モジュールが知っている前提**にする
- 利用側で `enable_api_xxx = true` のような flag を別途持たない (機能 on/off と二重管理になるため)
- 利用者が追加で必要とする API は `additional_apis` で拡張可能
- `disable_on_destroy = false` で運用する。Project 削除時に API を一括 disable すると他リソースに副作用が出るため
- `disable_dependent_services = true` を指定。意図しない依存 API 残留を防ぐ

</details>

---

## Always-on APIs

```
cloudresourcemanager.googleapis.com
serviceusage.googleapis.com
```

`iam.googleapis.com` is additionally enabled when any of `service_accounts`, `ci_service_account`, or `app_hosting` is on.

<details><summary>Ja</summary>

`iam.googleapis.com` は `service_accounts` / `ci_service_account` / `app_hosting` のいずれかが有効な場合に追加で有効化される。

</details>

---

## Per-feature mapping

| Feature variable | APIs enabled |
|------------------|--------------|
| `firebase` | `firebase.googleapis.com` |
| `apps` | `firebase.googleapis.com` (Firebase App registration requires the Firebase API even when `firebase = null`) |
| `authentication` | `identitytoolkit.googleapis.com` |
| `firestore` | `firestore.googleapis.com`, `firebaserules.googleapis.com` |
| `rtdb` | `firebasedatabase.googleapis.com` |
| `storage` | `firebasestorage.googleapis.com`, `storage.googleapis.com`, `firebaserules.googleapis.com` |
| `hosting` | `firebasehosting.googleapis.com` |
| `app_hosting` | `firebaseapphosting.googleapis.com`, `run.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com` |
| `data_connect` | `firebasedataconnect.googleapis.com`, `sqladmin.googleapis.com`, `cloudbilling.googleapis.com` |
| `fcm` | `fcm.googleapis.com` |
| `remote_config` | `firebaseremoteconfig.googleapis.com` |
| `app_check` | `firebaseappcheck.googleapis.com` |
| `crashlytics` | `firebasecrashlytics.googleapis.com` |
| `performance` | `firebaseperformance.googleapis.com` |
| `analytics` | `analyticsadmin.googleapis.com`, `firebase.googleapis.com` |
| `extensions` | `firebaseextensions.googleapis.com` |
| `secret_manager` | `secretmanager.googleapis.com` |
| `cloud_tasks` | `cloudtasks.googleapis.com` |
| `cloud_scheduler` | `cloudscheduler.googleapis.com` |
| `pubsub` | `pubsub.googleapis.com` |
| `eventarc` | `eventarc.googleapis.com` |
| `cloud_run` | `run.googleapis.com` |
| `cloud_functions` | `cloudfunctions.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`, `run.googleapis.com`, `eventarc.googleapis.com`, `pubsub.googleapis.com` (Gen2 Functions internally use Cloud Run / Eventarc / Pub/Sub) |

`distinct()` deduplicates the final list, so APIs requested by multiple features are only enabled once.

<details><summary>Ja</summary>

`distinct()` で重複排除されるため、複数機能で同じ API を要求しても 1 回しか有効化されない。

</details>

---

## Using `additional_apis`

For APIs outside the auto-derivation set. Each entry is validated to end with `.googleapis.com`.

```hcl
additional_apis = [
  "iap.googleapis.com",
  "cloudkms.googleapis.com",
]
```

Typical uses:

- Layering IAP (Identity-Aware Proxy)
- Envelope encryption with KMS
- Allowing an externally-managed Cloud Build trigger while still ensuring the API is on

<details><summary>Ja</summary>

自動判定外の API を有効化したい場合に使う。要素は `.googleapis.com` で終わるバリデーションが入っている。

利用ケース例:
- IAP (Identity-Aware Proxy) を別途使う
- KMS で envelope encryption する
- Cloud Build trigger を別管理ツールから使うが、本モジュール側でも API は有効化しておきたい

</details>

---

## Destroy behavior

Because `disable_on_destroy = false`, switching a feature variable back to `null` **does not disable the corresponding API**. The resources (Firestore database, Storage bucket, etc.) are destroyed, but the API itself remains enabled.

This is a deliberate choice that prioritizes "not breaking unrelated resources in the same Project". To explicitly disable an API, do it manually (gcloud).

<details><summary>Ja</summary>

`disable_on_destroy = false` のため、機能変数を `null` に変えても **対応する API は disable されない**。リソース (Firestore database, Storage bucket, etc.) は destroy されるが、API 自体は有効のまま残る。

これは「同じ Project 内の他リソースを破壊しない」ことを優先した設計判断。API を明示的に無効化したい場合は手動 (gcloud) で行う。

</details>
