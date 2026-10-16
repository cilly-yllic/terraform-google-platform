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

## v1.x → v2.0

v2.0.0 groups the grants to the runtime service accounts into one key per SA, with one list per grant scope (project / the SA itself / bucket). `service_accounts[]` gets the same `self_roles` / `bucket_roles` fields (additive). All SAs are now granted in one shape: `roles` / `self_roles` / `bucket_roles`.

| v1 key | v2 key |
|---|---|
| `app_hosting_compute_sa_roles` | `app_hosting_compute_sa.roles` |
| (none) | `app_hosting_compute_sa.self_roles` (new) |
| (none) | `app_hosting_compute_sa.bucket_roles` (new) |
| `default_compute_sa_roles` | `default_compute_sa.roles` |
| `default_compute_sa_self_roles` | `default_compute_sa.self_roles` |
| (none) | `default_compute_sa.bucket_roles` (new) |

```yaml
# v1
app_hosting_compute_sa_roles:
  - roles/cloudtasks.enqueuer
default_compute_sa_roles:
  - roles/secretmanager.secretAccessor
default_compute_sa_self_roles:
  - roles/iam.serviceAccountTokenCreator

# v2
app_hosting_compute_sa:
  roles:
    - roles/cloudtasks.enqueuer
default_compute_sa:
  roles:
    - roles/secretmanager.secretAccessor
  self_roles:
    - roles/iam.serviceAccountTokenCreator
```

The resource addresses of the existing grants (`google_project_iam_member.app_hosting_compute_extra[...]`, `google_project_iam_member.default_compute_extra[...]`, `google_service_account_iam_member.default_compute_self[...]`) are unchanged. After rewriting the keys, the plan shows **no changes**. No `moved` / `import` blocks are needed.

### Why the order matters

The dispatch Action passes only the keys it knows. If the Action and `settings.yml` are on different majors, the grants are not passed at all, and the plan **removes them**. Both v1.5.0 and v2.0.0 Actions stop (before creating a run) when they see the other major's keys, so the mismatch fails instead of dropping grants. Older Actions (≤ v1.4.0) do not have this guard.

The guard only checks the `settings.yml` each Action run reads. Two dispatches for the same workspace that overlap (one v1, one v2) can still mix the v1 root module with the v2 workspace variables. Do not let runs overlap while switching (steps 2–3), and turn off auto-apply so that a wrong plan is never applied.

### Steps (dispatch Action users)

1. **Before v2.0.0 reaches `main`: pin the Action to `@v1.5.0`.** `@main` follows the latest major, and a v2 Action with a v1 `module_version` fails every run. Keep `module_version: "~> 1.4"` (or `"~> 1.5"`). Run once and confirm the plan has no changes.
2. **Switch the Action, the module and the keys together**, with auto-apply off and no other run in flight:
   - Set `apply_policy: manual` (or otherwise make the environments require a manual apply) for the switch.
   - Wait for dispatches already running for these workspaces to finish, and do not start others until step 3 is done.
   - Action: `@v2.0.0`
   - `module_version: "~> 2.0"`
   - `settings.yml`: rewrite the keys as in the table above
   
   When `settings.yml` and the workflow are in different repositories, either can go first. Until both are merged, runs stop with an error pointing to this section; nothing is applied.
3. **Confirm the plan has no changes, then apply it and restore `apply_policy`.** If it destroys `app_hosting_compute_extra` / `default_compute_extra` / `default_compute_self`, a key was missed. Discard the run and fix `settings.yml`.
4. (Optional) **Narrow the grants in two applies.** To move a role from `roles` to `self_roles` / `bucket_roles` (e.g. `roles/iam.serviceAccountUser` to `self_roles`), first add it to the new scope and apply, check the app, and only then remove it from `roles` and apply again. Removing and adding in one apply runs both in parallel, so the SA can be without the permission for a moment.
   - The App Hosting compute SA always has `roles/firebaseapphosting.computeRunner`, which includes `storage.objects.*` on every bucket. Moving its Storage roles to `bucket_roles` does not narrow its access.

New projects can write the final form from the start; the steps above are only for existing projects.

### Steps (direct module users)

Rename the variables as in the table above and pin `version = "~> 2.0"`. Terraform rejects the removed v1 variables, so a missed rename fails at plan. Step 4 applies as well.

<details><summary>Ja</summary>

v2.0.0 は、実行 SA への付与を SA ごとに 1 つの key にまとめ、付与先の種類（project / SA 自身 / バケット）ごとに list を持つ形にした。`service_accounts[]` にも同じ `self_roles` / `bucket_roles` を足した（追加のみ）。すべての SA の付与が `roles` / `self_roles` / `bucket_roles` の 1 つの形になる。

| v1 の key | v2 の key |
|---|---|
| `app_hosting_compute_sa_roles` | `app_hosting_compute_sa.roles` |
| (なし) | `app_hosting_compute_sa.self_roles` (新規) |
| (なし) | `app_hosting_compute_sa.bucket_roles` (新規) |
| `default_compute_sa_roles` | `default_compute_sa.roles` |
| `default_compute_sa_self_roles` | `default_compute_sa.self_roles` |
| (なし) | `default_compute_sa.bucket_roles` (新規) |

既存の付与の resource アドレス（`google_project_iam_member.app_hosting_compute_extra[...]`、`google_project_iam_member.default_compute_extra[...]`、`google_service_account_iam_member.default_compute_self[...]`）は変えていない。key を書き換えた後の plan は**差分なし**になる。`moved` / `import` block は不要。

#### 順番が大事な理由

dispatch Action は、知っている key だけを terraform に渡す。Action と `settings.yml` の major がずれると付与がまったく渡らず、plan が**付与を消す**。v1.5.0 と v2.0.0 の Action は、もう一方の major の key を見つけると（run を作る前に）止まる。ずれは付与の消失ではなくエラーになる。v1.4.0 以前の Action にはこのガードが無い。

ガードは、各 Action の run が読んだ `settings.yml` しか確かめない。同じ workspace への dispatch が重なる（v1 と v2 が並行する）と、v1 の root module と v2 の workspace 変数が組み合わさることがある。切り替えの間（手順 2〜3）は run を重ねず、誤った plan が適用されないよう自動 apply を止める。

#### 手順（dispatch Action を使う場合）

1. **v2.0.0 が `main` に入る前に、Action を `@v1.5.0` に固定する。** `@main` は最新の major に追従し、v1 の `module_version` と v2 の Action の組み合わせでは全 run が失敗する。`module_version` は `"~> 1.4"`（または `"~> 1.5"`）のまま。一度 run し、plan に差分が無いことを確かめる。
2. **自動 apply を止め、ほかの run が無い状態で、Action・module・key を一緒に切り替える**:
   - 切り替えの間は `apply_policy: manual` にする（または対象環境の apply を手動にする）。
   - 対象 workspace へ走っている dispatch が終わるのを待ち、手順 3 が終わるまでほかの run を始めない。
   - Action: `@v2.0.0`
   - `module_version: "~> 2.0"`
   - `settings.yml`: 上の表のとおりに key を書き換える
   
   `settings.yml` と workflow が別のリポジトリにある場合、どちらを先にしてもよい。両方が入るまでの run は、この節を示すエラーで止まり、何も apply されない。
3. **plan に差分が無いことを確かめてから apply し、`apply_policy` を戻す。** `app_hosting_compute_extra` / `default_compute_extra` / `default_compute_self` の destroy が出たら key の書き換え漏れ。その run を破棄し、`settings.yml` を直す。
4. (任意) **付与を絞るときは apply を 2 回に分ける。** role を `roles` から `self_roles` / `bucket_roles` に移す（例: `roles/iam.serviceAccountUser` を `self_roles` へ）ときは、まず新しい付与先に足して apply し、アプリの動作を確かめてから、`roles` から外して再度 apply する。1 回の apply で外すと足すを同時に行うと並行に実行され、SA が一瞬その権限を失うことがある。
   - App Hosting の共有 compute SA は、常に `roles/firebaseapphosting.computeRunner` を持ち、これに全バケットの `storage.objects.*` が含まれる。Storage の role を `bucket_roles` に移しても、この SA の権限は狭まらない。

新しく作る project は最初から最終形を書けばよい。上の手順は既存の project のためのもの。

#### 手順（module を直接使う場合）

上の表のとおりに変数名を変え、`version = "~> 2.0"` に固定する。消えた v1 の変数は terraform が拒否するので、書き換え漏れは plan で止まる。手順 4 も同様。

</details>

---

## v2.0.0 (2026-10-16)

### Breaking changes
- The grants to the runtime service accounts are grouped into one key per SA: `app_hosting_compute_sa_roles` / `default_compute_sa_roles` / `default_compute_sa_self_roles` are replaced by `app_hosting_compute_sa` / `default_compute_sa` (`{ roles, self_roles, bucket_roles }`). See [v1.x → v2.0](#v1x--v20) for the migration. (#161)
- `dispatch-firebase-platform` stops when `settings.yml` still contains the removed v1 keys, or when a grant object has an unknown key, `null`, or a wrong shape (Terraform's object conversion would drop them and the plan would remove the grants). `service_accounts[]` entries with unknown keys are rejected too.

### Features
- `app_hosting_compute_sa.self_roles`: grant roles to the shared App Hosting compute SA **on itself**, e.g. `roles/iam.serviceAccountUser` for the Cloud Tasks OIDC token, instead of project-wide actAs.
- `bucket_roles` on all three kinds of SA (`app_hosting_compute_sa`, `default_compute_sa`, `service_accounts[]`): bucket-level grants on `storage.buckets[]` (by input name).
- `service_accounts[].self_roles` / `bucket_roles` (additive): every SA is now granted in one shape, `roles` / `self_roles` / `bucket_roles`.

### Upgrade notes
- Existing grants keep their resource addresses, so the plan after rewriting the keys has **no changes**.
- Follow [v1.x → v2.0](#v1x--v20): switch the Action, `module_version` and the keys together, with auto-apply off and no runs in flight.
- The App Hosting compute SA always has `roles/firebaseapphosting.computeRunner`, which includes `storage.objects.*` on every bucket; `bucket_roles` cannot narrow its Storage access.

<details><summary>Ja</summary>

- 実行 SA への付与を SA ごとに 1 つの key にまとめた: `app_hosting_compute_sa_roles` / `default_compute_sa_roles` / `default_compute_sa_self_roles` を `app_hosting_compute_sa` / `default_compute_sa`（`{ roles, self_roles, bucket_roles }`）に置き換えた。移行は [v1.x → v2.0](#v1x--v20) を参照。(#161)
- `dispatch-firebase-platform` は、消えた v1 の key が `settings.yml` に残っているとき、または付与の object に未知の key・`null`・形の誤りがあるときに止まる（terraform の object 変換が捨て、plan が付与を消すため）。`service_accounts[]` の未知の key も止める。
- `app_hosting_compute_sa.self_roles`: App Hosting の共有 compute SA に、**その SA 自身を対象として** role を付ける。例: Cloud Tasks の OIDC token 用の `roles/iam.serviceAccountUser` を、project 全体の actAs ではなく自分自身だけに絞る。
- 3 種の SA（`app_hosting_compute_sa`、`default_compute_sa`、`service_accounts[]`）に `bucket_roles`: `storage.buckets[]`（入力の名前）へのバケット単位の付与。
- `service_accounts[].self_roles` / `bucket_roles`（追加のみ）: すべての SA の付与が `roles` / `self_roles` / `bucket_roles` の 1 つの形になった。
- 既存の付与の resource アドレスは変えていない。key を書き換えた後の plan は**差分なし**。
- [v1.x → v2.0](#v1x--v20) に従い、自動 apply を止め、run を重ねない状態で、Action・`module_version`・key を一緒に切り替える。
- App Hosting の共有 compute SA は常に `roles/firebaseapphosting.computeRunner` を持ち、これに全バケットの `storage.objects.*` が含まれる。`bucket_roles` ではこの SA の Storage 権限を絞れない。

</details>

---

## v1.5.0 (2026-10-16)

### GitHub Actions
- `dispatch-firebase-platform` stops (before creating a run) when `settings.yml` contains keys from v2.0.0: `app_hosting_compute_sa`, `default_compute_sa`, `service_accounts[].self_roles`, `service_accounts[].bucket_roles`. A v1 Action does not know them; dropping them silently would leave the grants out of the run and the plan would **remove** them. This is the preparation release for the v1 → v2 migration. (#158)
- The Action README's usage examples pin the Action to a release tag together with `module_version`.

### Upgrade notes
- No module changes. Without the v2 keys, the behavior is the same as v1.4.0.
- **If your workflow uses `dispatch-firebase-platform@main`, pin it to `@v1.5.0` now.** `@main` will follow v2.0.0 once it is released, and a v2 Action with a v1 `module_version` fails every run.

<details><summary>Ja</summary>

- `dispatch-firebase-platform` は、`settings.yml` に v2.0.0 の key（`app_hosting_compute_sa`、`default_compute_sa`、`service_accounts[].self_roles`、`service_accounts[].bucket_roles`）があると、run を作る前に止まる。v1 の Action はこれらを知らず、黙って捨てると付与が run に渡らず、plan が付与を**消す**ため。v1 → v2 の移行の準備の版。(#158)
- Action の README の使用例を、Action のリリースタグと `module_version` の固定にそろえた。
- module の変更はない。v2 の key を書かなければ、挙動は v1.4.0 と同じ。
- **workflow が `dispatch-firebase-platform@main` を使っているなら、今のうちに `@v1.5.0` に固定する。** v2.0.0 のリリース後は `@main` が v2 に追従し、v1 の `module_version` と組み合わさると全 run が失敗する。

</details>

---

## v1.4.0 (2026-10-10)

### Features
- `authentication.blocking_functions.managed_by` (default `"terraform"`): who owns the blocking-function triggers. With `"deploy"`, the triggers that `firebase deploy` registers for `beforeUserCreated` / `beforeUserSignedIn` are kept (`ignore_changes`). Previously, a config without URIs **removed them on the next apply**: the provider's `blocking_functions` is not Computed. `"deploy"` cannot be combined with `before_create` / `before_sign_in`. (#154, #153)
- New submodule `modules/auth-deploy-managed`: the root module calls it instead of `modules/auth` when `managed_by = "deploy"`.

### Upgrade notes
- `modules/auth` and its config address (`module.auth[0].google_identity_platform_config.this`) are unchanged, so existing state and `import` blocks keep working. Omitting `managed_by` produces no diff.
- **Switching an existing config to `"deploy"`** (or back) moves it to another state address. Set `authentication.import_existing = true` in that apply. If you forget, the old address leaves state and the create fails. The config and triggers stay on GCP, and re-running with `import_existing = true` recovers. See [`modules/auth-deploy-managed`](../../modules/firebase-project-platform/modules/auth-deploy-managed/README.md#switching-the-mode-of-an-existing-config).
- When using `managed_by: deploy` with `import_existing` via the dispatch Action, update **both** the Action ref and `module_version` to this release. Older modules have no `auth_deploy_managed` import target.

<details><summary>Ja</summary>

- `authentication.blocking_functions.managed_by` (既定 `"terraform"`): blocking function の trigger の管理主体。`"deploy"` にすると、`firebase deploy` が `beforeUserCreated` / `beforeUserSignedIn` で登録した trigger を温存する (`ignore_changes`)。従来は URI を書かない config だと**次の apply で消えていた**。provider の `blocking_functions` が Computed でないため。`"deploy"` と `before_create` / `before_sign_in` は併用できない。(#154, #153)
- 新しい submodule `modules/auth-deploy-managed`: `managed_by = "deploy"` のとき、root module は `modules/auth` の代わりにこれを呼ぶ。
- `modules/auth` とその config のアドレス (`module.auth[0].google_identity_platform_config.this`) は変えていない。既存の state と `import` block はそのまま使える。`managed_by` を書かなければ差分は出ない。
- **既存 config を `"deploy"` に (または戻すように) 切り替える**と、state のアドレスが変わる。その apply で `authentication.import_existing = true` にする。忘れると旧アドレスが state から外れ、作成に失敗する。GCP 上の config と trigger は残るので、`import_existing = true` で再実行すれば復旧できる。[`modules/auth-deploy-managed`](../../modules/firebase-project-platform/modules/auth-deploy-managed/README.md#switching-the-mode-of-an-existing-config) 参照。
- dispatch Action で `managed_by: deploy` と `import_existing` を併用するときは、Action の ref と `module_version` の**両方**をこのリリースにそろえる。旧 module には import 先 `auth_deploy_managed` が無い。

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
