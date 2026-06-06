# Firebase Console / GCP IAM access

Human access to the project is expressed through the `users` variable.

Because Firebase Console authorizes on GCP IAM, granting `roles/viewer` / `roles/editor` / `roles/owner` automatically gives equivalent access in Firebase Console.

<details><summary>Ja</summary>

本モジュールが扱う「人間 (user) のアクセス権限」は `users` 変数で表現する。

Firebase Console は GCP IAM をベースに動作するため、`roles/viewer` / `roles/editor` / `roles/owner` を付与すれば Firebase Console にも自動的に同等の権限でアクセスできる。

</details>

---

## `users` variable structure

```hcl
users = [
  {
    email  = "dev-lead@example.com"
    role   = "editor"   # viewer | editor | owner
    deploy = true       # optional (default: false)
  },
  {
    email = "viewer@example.com"
    role  = "viewer"
  },
]
```

| Field | Required | Description |
|-------|:--------:|-------------|
| `email` | yes | User email (Google account) |
| `role` | no (default `"viewer"`) | One of `viewer` / `editor` / `owner` |
| `deploy` | no (default `false`) | `true` additionally grants roles needed for Cloud Functions / Artifact Registry deploys |

<details><summary>Ja</summary>

- `email` (required): user email (Google アカウント)
- `role` (default `"viewer"`): `viewer` / `editor` / `owner` のいずれか
- `deploy` (default `false`): `true` で Cloud Functions / Artifact Registry のデプロイに必要な roles も追加

</details>

---

## Granted roles

### `role` field

| `role` value | Granted roles |
|--------------|---------------|
| `viewer` | `roles/viewer` |
| `editor` | `roles/editor` |
| `owner` | `roles/owner` |

### Extra roles when `deploy = true`

```
roles/cloudfunctions.admin
roles/artifactregistry.reader
```

For cases like "viewer-only but performs manual deploys".

<details><summary>Ja</summary>

- `viewer` → `roles/viewer`
- `editor` → `roles/editor`
- `owner` → `roles/owner`

`deploy = true` の場合は `roles/cloudfunctions.admin` と `roles/artifactregistry.reader` が追加される。`viewer` だが手動デプロイは行う、というケースで使う。

</details>

---

## Member format

`users[].email` takes a Google account email directly. Internally it expands to the `user:<email>` IAM member.

For `group:` or `serviceAccount:` members, use `service_accounts` (which creates the SA and auto-grants roles) or manage `google_project_iam_member` separately (this module does not currently expose that surface).

<details><summary>Ja</summary>

`users[].email` は Google アカウントの email を直接指定する。内部的に `user:<email>` 形式の IAM member に展開される。

`group:` や `serviceAccount:` を扱いたい場合は `service_accounts` 変数 (SA 作成 + roles 自動付与) を使うか、別途 `google_project_iam_member` を呼び出す (本モジュールでは現状未対応)。

</details>

---

## Relationship with Firebase Console

Firebase Console authorizes against GCP IAM (Identity Platform / Firestore / Hosting all gate access on GCP IAM roles).

| GCP role | Behavior in Firebase Console |
|----------|------------------------------|
| `roles/viewer` | Read-only across features |
| `roles/editor` | Edit per feature; some Project settings still blocked |
| `roles/owner` | All operations including Project settings / IAM |

For finer-grained Firebase-specific roles (`roles/firebase.admin`, `roles/firebaseauth.admin`, etc.), prefer pushing them to `service_accounts` or external IAM management rather than `users` — it keeps responsibilities cleaner.

<details><summary>Ja</summary>

Firebase Console のアクセス権は GCP IAM をベースに判定される。より細かい Firebase 固有 role (`roles/firebase.admin`, `roles/firebaseauth.admin` 等) を付与したい場合は、`users` ではなく `service_accounts` / 外部の IAM 管理に寄せる方が責務分離しやすい。

</details>

---

## Best practices

- 1–2 `owner`s on production projects. Day-to-day developers get `editor` (+ `deploy = true`).
- Non-engineers get `viewer`.
- CI/CD goes through **`ci_service_account`**, not `users` (see [service-accounts.md](./service-accounts.md)).
- App backends use **`service_accounts`**, not `users`.

<details><summary>Ja</summary>

- 本番 Project には `owner` を 1〜2 名のみ。普段の開発者は `editor` (+ `deploy = true`)
- 非エンジニアは `viewer`
- CI/CD は **`users` ではなく `ci_service_account`** を使う ([service-accounts.md](./service-accounts.md))
- アプリのバックエンドが使う SA は **`service_accounts`** に列挙する (`users` には入れない)

</details>

---

## Examples

### Dev lead (editor + deploy) + viewer member

```hcl
users = [
  { email = "dev-lead@example.com", role = "editor", deploy = true },
  { email = "qa@example.com",       role = "viewer" },
]
```

### One owner + multiple editors

```hcl
users = [
  { email = "tech-lead@example.com", role = "owner" },
  { email = "dev-a@example.com",     role = "editor", deploy = true },
  { email = "dev-b@example.com",     role = "editor", deploy = true },
]
```
