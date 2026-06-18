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

## One-time setup (once per GitHub org)

The GitHub App installation + OAuth authorization is done **once per GitHub org**
and reused across all projects/environments. No per-env browser step.

1. **Install the Firebase GitHub App + authorize** on the GitHub org (browser).
   Create a Developer Connect connection once via the Firebase Console / Cloud
   Console and complete the `installation_state.action_uri` flow. Use a
   **robot / shared GitHub account** (not a personal account) so the connection
   does not break when an individual leaves or loses repo access.
2. **Capture two values** from that authorization:
   - `app_installation_id` — the org-level GitHub App installation id (reusable).
   - the **OAuth token** that authorizes the connection (store securely).

These two values are reused for every environment. Terraform never holds the GitHub
token itself — the GitHub↔GCP trust lives in the GCP-side connection.

<details><summary>Ja</summary>

GitHub App のインストール + OAuth 認可は **GitHub 組織あたり1回**だけ実施し、
全プロジェクト/環境で使い回す。env ごとのブラウザ手順は発生しない。

1. **Firebase GitHub App をインストール + 認可** (ブラウザ)。Firebase コンソール /
   Cloud コンソールで connection を1回作り、`installation_state.action_uri` の
   フローを完了する。個人アカウントではなく **robot / 共有アカウント**を使う
   (担当者の退職や権限喪失で連携が壊れないように)。
2. その認可から **2つの値**を取得する:
   - `app_installation_id` — 組織レベルの GitHub App インストール ID (再利用可)
   - connection を認可する **OAuth token** (安全に保管)

この2値を全環境で使い回す。Terraform は GitHub token を保持しない —
GitHub↔GCP の信頼は GCP 側の connection が持つ。

</details>

---

## Per-environment setup

### 1. Inject the OAuth token into the target project's Secret Manager

The connection reads the OAuth token from Secret Manager in the **target Firebase
project**. There are two ways to get it there:

**(A) Let Terraform create the secret (recommended, fully automated).** Pass the token
to **Action B** via its `github_oauth_token` input (sourced from a GitHub Actions
secret in the consumer repo, e.g. `secrets.APPHOSTING_GITHUB_OAUTH_TOKEN`). Action B
injects it as a **sensitive** Terraform variable per workspace, and the module creates
`google_secret_manager_secret` + `_version` in the target project automatically. No
per-project manual step. Trade-off: the token value is stored in TFC state (sensitive,
encrypted at rest).

`app_installation_id` (org-level, stable, non-sensitive) is passed the same way —
via Action B's `github_app_installation_id` input from a repo **Variable** — so the
org-wide value is not duplicated in every service's `settings.yml`:

```yaml
# consumer workflow (configure-platform.yml) calling Action B
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@...
  with:
    # ...
    github_oauth_token:          ${{ secrets.APPHOSTING_GITHUB_OAUTH_TOKEN }}
    github_app_installation_id:  ${{ vars.GITHUB_APP_INSTALLATION_ID }}
```

Get the installation id with:
`gh api /orgs/<org>/installations --jq '.installations[] | "\(.id)\t\(.app_slug)"'`.
The Action input takes precedence over `github_connection.app_installation_id` in
`settings.yml` (which remains as a fallback).

**(B) Reference a pre-existing secret (token never in TFC state).** Omit
`github_oauth_token`; inject the secret yourself once per project and the module just
references it:

```sh
printf '%s' "$TOKEN" | gcloud secrets create apphosting-github-oauth-token \
  --project=cmonoth-dev-004 --replication-policy=automatic --data-file=-
# rotate: gcloud secrets versions add apphosting-github-oauth-token --project=... --data-file=-
```

### 2. Configure `settings.yml`

```yaml
firebase_platform:
  apps:
    - name: task-tree-web-app
      type: web
  app_hosting:
    - backend_id: task-tree-web-app
      app: task-tree-web-app
      branch: main                              # 監視ブランチ (push で自動 rollout) → git 連携の signal
      root_directory: apps/task-tree/web-app    # repo 内の web app ルート
      # repo (clone_uri) は通常書かない。Action B が service repo から自動注入する。
  github_connection:
    oauth_token_secret: apphosting-github-oauth-token  # secret 名 (作成先 / 参照先)
    # app_installation_id は Action B の github_app_installation_id input (repo Variable)
    # で渡すのが推奨。settings.yml に書く場合のみ app_installation_id: "12345678" を追加。
```

A backend is treated as **git-connected** when it has `branch` and/or `root_directory`
(and/or an explicit `repo`); a "bare backend" (none of these) keeps the legacy
non-git behavior. The clone_uri is normally **not** written in `settings.yml` — Action B
derives `https://github.com/<owner>/<service>.git` from the service repo it is
processing and injects it via the `app_hosting_repo` input (override per-backend with
`repo` only when a backend points at a different repository). Neither the token nor
(preferably) the installation id is written in `settings.yml` either — both flow via
Action B inputs (`github_oauth_token` / `github_app_installation_id`).

<details><summary>Ja</summary>

### 1. 対象プロジェクトの Secret Manager に OAuth token を用意

connection は OAuth token を **対象 Firebase プロジェクト**の Secret Manager から読む。
入れ方は2通り:

- **(A) terraform に作らせる (推奨・全自動)**: token を **Action B** の
  `github_oauth_token` input に渡す (消費側 repo の GitHub Secret 由来、例
  `secrets.APPHOSTING_GITHUB_OAUTH_TOKEN`)。Action B が sensitive な terraform 変数として
  各 workspace に注入し、module が対象プロジェクトに secret + version を自動作成する。
  プロジェクトごとの手動投入は不要。トレードオフ: token 値が TFC state に乗る
  (sensitive・暗号化保存)。
- **(B) 既存 secret を参照 (state に乗せない)**: `github_oauth_token` を渡さず、
  自分で secret を投入して module は参照のみ行う (上記 gcloud one-liner)。

### 2. `settings.yml` を設定

`branch` / `root_directory` のいずれかがあれば git 連携 backend と判定される
(何も無ければ従来の "bare backend")。clone_uri (`repo`) は通常書かず、Action B が
service repo から `app_hosting_repo` として自動注入する (別 repo を指す backend のみ
`repo` で上書き)。token / installation id も `settings.yml` に書かず Action B input 経由。

</details>

---

## What Terraform creates

For each git-connected `app_hosting` backend (has `branch` / `root_directory` / `repo`),
with `github_connection` provided, the module creates (non-interactively, no browser):

- `google_developer_connect_connection` (`github_config.github_app = "FIREBASE"`,
  `app_installation_id`, `authorizer_credential.oauth_token_secret_version`)
- a service-identity for `developerconnect.googleapis.com` + `secretAccessor` on the
  OAuth token secret (so the connection can read it)
- `google_secret_manager_secret` + `_version` **when `github_oauth_token` is provided**
  (mode A); otherwise an existing secret is referenced (mode B)
- `google_developer_connect_git_repository_link` per unique repo
- `google_firebase_app_hosting_backend.codebase { repository, root_directory }`
- `google_firebase_app_hosting_traffic.rollout_policy { codebase_branch }` (only when
  `branch` is set)

## Runtime (every deploy)

Push to the watched branch → App Hosting builds the source and rolls it out. The CI
SA is **not** granted any App Hosting role (see `ci_sa_auto_roles` in `main.tf`); CI
only needs to `git push`.

<details><summary>Ja</summary>

`app_hosting[].repo` を指定し `github_connection` を渡すと、module は (非対話・ブラウザ
不要で) connection / service-identity + secretAccessor / repo link / backend.codebase /
traffic.rollout_policy を作成する。

運用時は監視ブランチへ push するだけで App Hosting がビルド & ロールアウトする。
CI SA には App Hosting ロールを付与しない (`main.tf` の `ci_sa_auto_roles` 参照)。
CI は `git push` だけでよい。

</details>
