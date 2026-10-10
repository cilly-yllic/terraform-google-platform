# Upgrade guide

Tracks breaking changes between Registry versions in chronological order.

Releases are listed at [GitHub Releases](https://github.com/cilly-yllic/terraform-google-platform/releases).

<details><summary>Ja</summary>

Registry バージョン間の breaking change を時系列で記録する。

各リリースは [GitHub Releases](https://github.com/cilly-yllic/terraform-google-platform/releases) で参照可能。

</details>

---

## v0.x → v1.0 (toward the initial Registry release)

Before publishing to the Registry, batching breaking changes is acceptable. From `v1.0.0` onward, the module follows SemVer and breaking changes only occur on **major bumps**.

<details><summary>Ja</summary>

Registry 公開前は破壊的変更を集約することを許容する。`v1.0.0` 以降は SemVer に従い、破壊的変更は **major bump のみ** で行う。

</details>

---

## v1.x policy

- **Adding a new feature variable**: minor bump (`v1.x.0`)
- **Default-value change that produces a side effect**: minor bump + a CHANGELOG warning
- **Type change or removal of an existing variable**: major bump (`v2.0.0`)
- **Removing or renaming a submodule output**: major bump
- **A repo-wide convention change (e.g. defaulting `firebase` to `null`)**: major bump

<details><summary>Ja</summary>

- **新規機能変数の追加**: minor bump (`v1.x.0`)
- **既定値の変更で副作用が発生するもの**: minor bump + CHANGELOG で警告
- **既存変数の型変更 / 削除**: major bump (`v2.0.0`)
- **submodule の output 削除 / rename**: major bump
- **`firebase` 既定値を `null` 化** するような全体方針変更: major bump

</details>

---

## Compatibility checklist (at PR review time)

Before introducing a new breaking change:

- [ ] Does `terraform plan` for an existing user produce a **destructive diff**?
- [ ] Are you renaming or removing any outputs?
- [ ] For changes like `null` → `true` that only affect API enablement, are side effects minimal?
- [ ] Should the CHANGELOG include a migration step?

<details><summary>Ja</summary>

新たな破壊的変更を入れる前に確認するチェックリスト:

- 既存利用者の `terraform plan` で **削除を伴う diff** が出ないか
- outputs の rename / 削除を伴っていないか
- 機能変数の `null` → `true` 等で API 有効化のみ変わるパターンは副作用最小か
- CHANGELOG に migration 手順を書く必要があるか

</details>

---

## v1.3.0 (2026-10-10)

### Features
- `authentication.upgrade_to_identity_platform` (default `true`): controls whether the Identity Platform config is created, i.e. whether the project is **upgraded to Identity Platform** (`initializeAuth`, which cannot be undone). `false` only enables `identitytoolkit.googleapis.com` and IAM. It cannot be combined with `import_existing` / `blocking_functions` / `authorized_domains`; the plan fails validation if it is. (#150)
- `authentication.import_existing` (default `false`): imports a config that was already upgraded from the Console instead of creating it (creating it again would fail). `import` blocks are only allowed in the root module, so the dispatch Action's root template contains the block. **When calling the module directly**, add the block to your root module (see [`modules/auth`](../../modules/firebase-project-platform/modules/auth/README.md#upgrading-to-identity-platform)). Once imported, the block is a no-op, so the flag can stay `true`. (#150)

### Upgrade notes
- Both flags are opt-in. Omitting them produces no diff.

<details><summary>Ja</summary>

- `authentication.upgrade_to_identity_platform` (既定 `true`): Identity Platform config を作成するか、つまり project を **Identity Platform にアップグレードする**か (`initializeAuth`。取り消せない) を制御する。`false` なら `identitytoolkit.googleapis.com` の有効化と IAM のみ行う。`import_existing` / `blocking_functions` / `authorized_domains` とは併用できず、併用すると plan が validation エラーになる。(#150)
- `authentication.import_existing` (既定 `false`): Console でアップグレード済みの config を作成せず import する (作成しようとすると失敗する)。`import` block は root module にしか書けないため、dispatch Action の root テンプレートに block を入れた。**module を直接呼ぶ場合**は自分の root module に block を書く ([`modules/auth`](../../modules/firebase-project-platform/modules/auth/README.md#upgrading-to-identity-platform) 参照)。取り込み後は no-op なので flag は `true` のままでよい。(#150)
- いずれも opt-in。書かなければ差分は出ない。

</details>

---

## v1.2.0 (2026-10-10)

### Features
- `default_compute_sa_self_roles`: grants roles to the Compute Engine default SA **on itself** (`google_service_account_iam_member`; both the resource and the member are the default compute SA). Typical use: `roles/iam.serviceAccountTokenCreator` for the Firebase Admin SDK's `createCustomToken` without a key file (it signs via `signBlob`). Unlike `default_compute_sa_roles` (project-level), it does not let the runtime SA sign as other SAs in the project. When non-empty, `iamcredentials.googleapis.com` is enabled automatically. Omitting it produces no diff. (#145, #144)

### Bug fixes
- Plans that change the API set (`additional_apis`, enabling a feature, etc.) no longer replace (`-/+`) the IAM bindings of the default compute SA (`run.invoker` / `eventarc.eventReceiver` / `default_compute_sa_roles` / `default_compute_sa_self_roles` / the Firestore backup export SA when `export_platform = "cloud_run"`). Previously `data.google_project` was deferred to apply, the SA email became unknown, and the bindings were briefly removed during apply. (#147, #146)

### Upgrade notes
- The always-on APIs (`cloudresourcemanager` / `serviceusage`) moved from `google_project_service.this` to `google_project_service.base`. `moved` blocks carry the state over: the first plan shows two "has moved to" entries and no changes.
- **Only if you call the `modules/storage` submodule directly** with `firestore_backup.export_platform = "cloud_run"`: pass the new `compute_default_sa` input (`<project-number>-compute@developer.gserviceaccount.com`). Without it, the plan fails with a precondition error. Calling the root module (or the dispatch Action) needs no change.

<details><summary>Ja</summary>

- `default_compute_sa_self_roles`: 既定 compute SA に、**その SA 自身を対象として** role を付与する (`google_service_account_iam_member`。resource も member も既定 compute SA)。代表例は Firebase Admin SDK の `createCustomToken` を鍵ファイルなしで使うための `roles/iam.serviceAccountTokenCreator` (`signBlob` で署名する)。project-level の `default_compute_sa_roles` と違い、プロジェクト内の他 SA への署名権限は増えない。非空なら `iamcredentials.googleapis.com` を自動で有効化する。省略時は差分なし。(#145, #144)
- API 構成が変わる plan (`additional_apis` の変更、機能の追加など) で、既定 compute SA の IAM binding (`run.invoker` / `eventarc.eventReceiver` / `default_compute_sa_roles` / `default_compute_sa_self_roles` / `export_platform = "cloud_run"` の Firestore backup export SA) が置き換え (`-/+`) にならなくなった。従来は `data.google_project` の読み込みが apply まで遅延して SA email が unknown になり、apply 中に binding が一時的に外れていた。(#147, #146)
- 常時有効の API (`cloudresourcemanager` / `serviceusage`) を `google_project_service.this` から `google_project_service.base` に移した。`moved` で state を引き継ぐため、初回 plan は「has moved to」が 2 件出るだけで変更はない。
- **`modules/storage` サブモジュールを直接呼び**、`firestore_backup.export_platform = "cloud_run"` を使っている場合のみ: 新しい入力 `compute_default_sa` (`<project-number>-compute@developer.gserviceaccount.com`) を渡すこと。渡さないと precondition エラーで plan が止まる。root module (または dispatch Action) 経由なら対応不要。

</details>

---

## v1.1.0 (2026-10-08)

### Provider support
- `hashicorp/google` / `hashicorp/google-beta`: the upper bound is raised from `< 8.0` to `< 9.0` (lower bound `>= 6.0` unchanged). None of the resources used by this module are affected by the [v8 breaking changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/version_8_upgrade).
  - **Calling the module directly**: your own lock file / version constraint decides. Run `terraform init -upgrade` to move to 8.x.
  - **Via the dispatch Action**: no lock file is uploaded, so the first run after updating picks the **latest 8.x automatically**. Provider 8.x rewrites the state schema, so going back to 7.x requires restoring state. To stay on 7.x, pin `module_version` to a release before this one. We recommend running a plan once and confirming it is a no-op.

### GitHub Actions
- `dispatch-firebase-platform` / `dispatch-project-bootstrap` now run on the **`node24`** runtime (GitHub is retiring `node20`). GitHub-hosted runners are unaffected; self-hosted / GHES runners need **runner v2.327.1 or later**.

### Features
- `storage.buckets[].cors`: CORS rules for additional buckets (same names/semantics as the `google_storage_bucket` `cors` block). Omitting it produces no diff. (#132)
- `app_hosting[].environment`: selects `apphosting.<environment>.yaml` for the backend. Omitting it produces no diff. (#129)
- Cloud SQL users from settings: `CLOUD_IAM_USER` via `users[].cloud_sql`, `BUILT_IN` via `data_connect[].cloud_sql.users[]` (passwords injected through the dispatch Action's `cloud_sql_secrets` input). Opt-in; nothing is created unless declared. (#128)

<details><summary>Ja</summary>

- `hashicorp/google` / `google-beta` の上限を `< 8.0` → `< 9.0` に引き上げ (下限 `>= 6.0` は据え置き)。本モジュールが使うリソースに v8 の破壊的変更の該当はない。
  - **module を直接呼ぶ場合**: 利用側の lock file / version 制約に従う。8.x に上げるなら `terraform init -upgrade`。
  - **dispatch Action 経由の場合**: lock file を upload しないため、更新後の初回 run で **8.x の最新に自動で上がる**。8.x は state schema を書き換えるため 7.x へ戻すには state の復元が必要。7.x に留めたい場合は `module_version` を本リリースより前に pin する。一度 plan を流して no-op を確認することを推奨。
- dispatch Action 2 種は **`node24`** runtime で動作 (GitHub の `node20` 廃止に追従)。GitHub-hosted runner は影響なし、self-hosted / GHES は **runner v2.327.1 以上** が必要。
- `storage.buckets[].cors`: 追加 bucket に CORS ルールを指定可能に (`google_storage_bucket` の `cors` ブロックと同名・同義)。省略時は差分なし。(#132)
- `app_hosting[].environment`: backend が使う `apphosting.<environment>.yaml` を指定可能に。省略時は差分なし。(#129)
- settings から Cloud SQL ユーザーを宣言可能に (`CLOUD_IAM_USER` は `users[].cloud_sql`、`BUILT_IN` は `data_connect[].cloud_sql.users[]`。password は dispatch Action の `cloud_sql_secrets` input で注入)。宣言しなければ何も作られない (opt-in)。(#128)

</details>

---

## Future entries (template)

```
## v1.x.0 (YYYY-MM-DD)

### Breaking changes
- `<variable>`: <what changed>. <migration steps>.

### Features
- <feature>: <summary>

### Bug fixes
- <title>
```

Stack new releases on top of this template as they happen.

<details><summary>Ja</summary>

実際の breaking change が発生した際にこのテンプレートを上に積む形で運用する。

</details>
