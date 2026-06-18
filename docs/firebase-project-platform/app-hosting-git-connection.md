# App Hosting — git connection (Developer Connect) model

App Hosting backends can deploy by **connecting a GitHub repository** (via Developer
Connect) instead of pushing builds from CI. On every push to the watched branch,
App Hosting's own service agents build the source and roll it out. **CI needs zero
GCP permissions — it only does `git push`.**

This avoids the `iam.serviceAccounts.create` / owner permission escalation that the
`firebase deploy --only apphosting` path requires, and keeps the App Hosting backend
fully managed by Terraform without state pollution.

<details><summary>Ja</summary>

App Hosting backend は CI からビルドを push する代わりに、**GitHub リポジトリを
connect する (Developer Connect 経由)** デプロイができる。監視ブランチへ push する
たびに App Hosting 側のサービスエージェントがソースをビルドしてロールアウトする。
**CI に GCP 権限は一切不要 — `git push` だけ。**

これにより `firebase deploy --only apphosting` が要求する
`iam.serviceAccounts.create` / owner 級の権限昇格を回避でき、かつ backend を
Terraform でフル管理したまま state 汚染も起きない。

</details>

---

## Why no state pollution

Terraform owns the stable layer (connection / repo link / backend / **rollout
policy incl. watched branch**). The per-push **builds / rollouts / traffic shifts**
are App Hosting runtime artifacts that Terraform does **not** manage.

- `google_firebase_app_hosting_traffic` is configured with **`rollout_policy` only**
  (watched branch). `target.splits` is never set, and `current.splits` is
  output-only — so App Hosting's automatic per-push traffic shift never conflicts
  with Terraform state.
- `google_firebase_app_hosting_build` is **not** managed (each push creates a new
  build that would otherwise drift continuously).

<details><summary>Ja</summary>

Terraform は安定レイヤー (connection / repo link / backend / **監視ブランチを含む
rollout policy**) を所有する。push ごとの **build / rollout / traffic 配分** は
App Hosting のランタイム成果物で Terraform は管理しない。

- `google_firebase_app_hosting_traffic` は **`rollout_policy` だけ**を設定する
  (監視ブランチ)。`target.splits` は書かず、`current.splits` は output-only なので、
  push ごとの自動 traffic 配分が Terraform state と衝突しない。
- `google_firebase_app_hosting_build` は管理しない (push ごとに新 build が出来て
  drift し続けるため)。

</details>

---

## Setup — two phases (`github_app = "FIREBASE"`)

A FIREBASE connection uses **no OAuth token and no Secret Manager secret**. Terraform
creates the connection in a **PENDING** state with just `github_app = "FIREBASE"`; a
human authorizes it once in the browser; then Terraform links the repo. This is a
**two-phase** flow controlled by the `app_hosting_git_ready` flag.

### `settings.yml`

```yaml
firebase_platform:
  apps:
    - name: task-tree-web-app
      type: web
  app_hosting:
    - backend_id: task-tree-web-app
      app: task-tree-web-app
      branch: main                              # 監視ブランチ (push で自動 rollout)
      root_directory: apps/task-tree/web-app    # repo 内の web app ルート
      # repo (clone_uri) は通常書かない。Action B が service repo から自動注入する。
  # app_hosting_git_ready: true   # ← フェーズ2 で有効化 (下記)
```

### Phase 1 — create the connection (PENDING)

Deploy with `app_hosting_git_ready` **unset/false** (default). Terraform creates the
Developer Connect connection (PENDING) and a **bare** backend (no codebase yet, no repo
link).

### Authorize (one-time, browser)

Find the install URI and complete it (installs/authorizes the Firebase GitHub App; use a
**robot / shared GitHub account**):

```sh
gcloud developer-connect connections describe github \
  --location=<region> --project=<firebase-project>   # → installationState / action(install) URI
```
Open the URI, authorize. Re-describe until `installationState` is `COMPLETE`.

### Phase 2 — link the repo

Set **`app_hosting_git_ready: true`** in `settings.yml` and re-run Action B. Terraform now
creates the `git_repository_link`, the backend `codebase`, and the `traffic.rollout_policy`
(watched branch) against the now-COMPLETE connection.

### Deploy

Push to the watched branch (delivery branch) → App Hosting builds & rolls out. CI needs
**zero GCP permissions** (`git push` only).

<details><summary>Ja</summary>

FIREBASE connection は **OAuth token も secret も使わない**。terraform が
`github_app="FIREBASE"` だけで connection を **PENDING** 作成 → 人間がブラウザで一度認可 →
terraform が repo を連携、という **2 フェーズ**。`app_hosting_git_ready` フラグで制御する。

1. **フェーズ1**: `app_hosting_git_ready` 未設定(false)で deploy → connection (PENDING) と
   bare backend を作成。
2. **認可 (ブラウザ・一度)**: `gcloud developer-connect connections describe github
   --location=<region> --project=<project>` で install URI を取得 → 開いて Firebase GitHub
   App を認可 (robot / 共有アカウント推奨)。`installationState` が `COMPLETE` になるまで待つ。
3. **フェーズ2**: `settings.yml` に `app_hosting_git_ready: true` を追加して Action B 再実行 →
   repo link / codebase / rollout_policy を作成。
4. **デプロイ**: 監視ブランチへ push → App Hosting が自動ビルド&ロールアウト (CI 権限ゼロ)。

注: `branch` / `root_directory` のいずれかで git 連携 backend と判定。clone_uri は Action B
が自動注入。

</details>

---

## What Terraform creates

For each git-connected `app_hosting` backend (has `branch` / `root_directory` / `repo`)
the module creates (non-interactively):

- `google_developer_connect_connection` — `github_config { github_app = "FIREBASE",
  app_installation_id }` のみ。**authorizer_credential / OAuth token secret は無し**
- `google_developer_connect_git_repository_link` per unique repo
- `google_firebase_app_hosting_backend.codebase { repository, root_directory }`
- `google_firebase_app_hosting_traffic.rollout_policy { codebase_branch }` (only when
  `branch` is set)

## Runtime (every deploy)

Push to the watched branch → App Hosting builds the source and rolls it out. The CI
SA is **not** granted any App Hosting role (see `ci_sa_auto_roles` in `main.tf`); CI
only needs to `git push`.

<details><summary>Ja</summary>

git 連携 backend に対し module は connection (FIREBASE + app_installation_id のみ) /
repo link / backend.codebase / traffic.rollout_policy を作成する。OAuth token / secret /
secretAccessor は作らない。

運用時は監視ブランチへ push するだけで App Hosting がビルド & ロールアウトする。
CI SA には App Hosting ロールを付与しない (`main.tf` の `ci_sa_auto_roles` 参照)。
CI は `git push` だけでよい。

</details>
