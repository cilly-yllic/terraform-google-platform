# modules/firestore

Submodule that creates the Cloud Firestore **default database + optional additional databases + an initial ruleset**.

<details><summary>Ja</summary>

Cloud Firestore の **デフォルト database + 任意の追加 database + 初期 ruleset** を作成する submodule。

</details>

## Resources created

| Resource | Role |
|----------|------|
| `google_firestore_database.default` | Always creates the default database (`(default)`) |
| `google_firebaserules_ruleset.default` | A **deny-all** ruleset for the default database |
| `google_firebaserules_release.default` | Releases the ruleset to `cloud.firestore` |
| `google_firestore_database.additional` | Additional databases from `databases[]` |

## Initial ruleset (deny-all)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

A placeholder rule on the assumption that "security rules are not seriously managed in Terraform". Production rules are expected to be deployed via Firebase CLI (`firebase deploy --only firestore:rules`).

<details><summary>Ja</summary>

「Terraform で security rules を本気で管理しない」前提のプレースホルダ。本番ルールは Firebase CLI (`firebase deploy --only firestore:rules`) でデプロイする想定。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Default DB location |
| `type` | `string` | `"FIRESTORE_NATIVE"` | `FIRESTORE_NATIVE` / `DATASTORE_MODE` |
| `delete_protection_state` | `string` | `"DELETE_PROTECTION_DISABLED"` | `DELETE_PROTECTION_DISABLED` / `DELETE_PROTECTION_ENABLED` |
| `point_in_time_recovery` | `bool` | `false` | Enable PITR |
| `databases` | `list(object)` | `[]` | Additional databases (`database_id`, `location`, `type`, `delete_protection_state`, `point_in_time_recovery`) |

## Outputs

| Name | Description |
|------|-------------|
| `default_database_name` | Default DB resource name |
| `default_database_location` | Default DB location |
| `additional_databases` | `{ database_id => name }` map |

## Related APIs

- `firestore.googleapis.com`
- `firebaserules.googleapis.com`

## Invocation condition

Called when `var.firestore != null`.
