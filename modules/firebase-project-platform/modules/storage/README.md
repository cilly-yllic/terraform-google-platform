# modules/storage

Submodule that creates the Cloud Storage for Firebase **default bucket + additional buckets + optional Firestore-backup bucket + an initial ruleset**.

<details><summary>Ja</summary>

Cloud Storage for Firebase の **デフォルト bucket + 追加 bucket + 任意の Firestore backup bucket + 初期 ruleset** を作成する submodule。

</details>

## Resources created

| Resource | Role |
|----------|------|
| `google_firebase_storage_bucket.default` | Registers the default bucket (`{project}.firebasestorage.app`) with Firebase Storage |
| `google_firebaserules_ruleset.storage` | A **deny-all** ruleset for the default bucket |
| `google_firebaserules_release.storage` | Releases the ruleset to `firebase.storage/{bucket}` |
| `google_storage_bucket.additional` | GCS buckets specified via `buckets[]` |
| `google_firebase_storage_bucket.additional` | Registers each additional bucket with Firebase Storage |
| `google_storage_bucket_iam_member.additional` | IAM bindings on additional buckets |
| `google_storage_bucket.firestore_backup` | (optional) Firestore-export bucket |
| `google_project_iam_member.firestore_backup_*` | (optional) Bucket-write IAM for the Firestore export SA |

## Initial ruleset (deny-all)

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

Production rules are expected to be deployed via Firebase CLI (`firebase deploy --only storage:rules`).

<details><summary>Ja</summary>

本番ルールは Firebase CLI (`firebase deploy --only storage:rules`) でデプロイする想定。

</details>

## Bucket naming

- `buckets[].name` is **automatically prefixed with `{project}-`** (e.g. `name = "uploads"` produces a bucket called `{project}-uploads`).
- Set `buckets[].raw_name = true` to skip the prefix and use `name` verbatim (only when you need globally-unique custom naming).

<details><summary>Ja</summary>

- `buckets[].name` は **`{project}-` prefix が自動付与** される (例: `name = "uploads"` → 実際の bucket は `{project}-uploads`)
- `buckets[].raw_name = true` を指定すると prefix を付けずに `name` をそのまま使う (グローバル一意な命名にしたい場合のみ)

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Default bucket location |
| `buckets` | `list(object)` | `[]` | Additional buckets. Fields: `name`, `raw_name`, `location`, `storage_class`, `iams[]` |
| `firestore_backup` | `object \| null` | `null` | Firestore-backup bucket config |

Fields of `firestore_backup`:

| Field | Default | Description |
|-------|---------|-------------|
| `bucket_name` | `"firestore-backups"` | suffix (`{project}-<suffix>`) |
| `export_platform` | `"cloud_functions"` | `cloud_functions` / `cloud_run`. Selects which SA is granted bucket-write IAM. |
| `soft_delete_policy.retention_duration_seconds` | `0` | Soft-delete retention seconds |

## Outputs

| Name | Description |
|------|-------------|
| `default_bucket` | Default bucket name |
| `additional_buckets` | `{ input_name => resolved_GCS_name }` |
| `firestore_backup_bucket` | Backup bucket name (`null` if not configured) |

## Related APIs

- `firebasestorage.googleapis.com`
- `storage.googleapis.com`
- `firebaserules.googleapis.com`

## Invocation condition

Called when `var.storage != null`.
