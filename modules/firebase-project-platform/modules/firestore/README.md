# modules/firestore

Submodule that creates Cloud Firestore **databases (one per `databases[]` entry)** plus an optional project-level initial ruleset.

There is no special "default database" — every entry in `databases[]` is treated equally, including `"(default)"` if the caller chooses to declare it. The database list is built by the root module from the `firestore` variable.

<details><summary>Ja</summary>

`databases[]` の各 entry ごとに Cloud Firestore database を作成する submodule (任意で project-level の初期 ruleset も)。

特別な「default database」は存在せず、`"(default)"` を含めるかどうかは利用者判断。すべての entry が対等に扱われる。database list はルートモジュールが `firestore` 変数から組み立てて渡す。

</details>

## Resources created

| Resource | Role |
|----------|------|
| `google_firestore_database.this` | Databases (`for_each` over `databases[]`, keyed by `database_id`) |
| `google_firebaserules_ruleset.default` | A **deny-all** ruleset (only when `apply_default_rules = true` and at least one database exists) |
| `google_firebaserules_release.default` | Releases the deny-all ruleset to `cloud.firestore` at the project level (same condition) |

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
| `default_location` | `string` | (required) | Fallback location used when a `databases[]` entry omits `location` |
| `databases` | `list(object)` | `[]` | Databases to create. Each: `database_id` (required), `location`, `type` (default `"FIRESTORE_NATIVE"`), `delete_protection_state` (default `"DELETE_PROTECTION_DISABLED"`), `point_in_time_recovery` (default `false`) |
| `apply_default_rules` | `bool` | `true` | Attach the project-level deny-all initial ruleset to `cloud.firestore`. Disable when bootstrapping rules via Firebase CLI. |

## Outputs

| Name | Description |
|------|-------------|
| `databases` | Map keyed by `database_id`. Each value contains `name`, `location`, `type`. |

## Related APIs

- `firestore.googleapis.com`
- `firebaserules.googleapis.com`

## Invocation condition

Called when `var.firestore != null`.
