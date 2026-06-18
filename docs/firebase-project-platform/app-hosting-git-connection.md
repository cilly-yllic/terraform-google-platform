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

`github_app = "FIREBASE"` connections do **not** use an OAuth token or a Secret
Manager secret. The GitHub↔GCP authorization is established by **installing the
Firebase App Hosting GitHub App on the org once** (browser); Developer Connect then
holds the credential internally. Terraform only needs the **installation id**.

1. **Install the Firebase App Hosting GitHub App on the GitHub org** (browser, once).
   Use a **robot / shared GitHub account** (not a personal one) so it does not break
   when an individual leaves. (Doing it via the Firebase Console App Hosting setup,
   or the Cloud Console Developer Connect flow, both work.)
2. **Capture the `app_installation_id`** (org-level, reusable, non-sensitive):
   `gh api /orgs/<org>/installations --jq '.installations[] | "\(.id)\t\(.app_slug)"'`

That's the only one-time step. There is **no OAuth token to copy** and nothing to put
in Secret Manager.

<details><summary>Ja</summary>

`github_app = "FIREBASE"` の connection は **OAuth token も Secret Manager secret も使わない**。
GitHub↔GCP の認可は **組織への Firebase App Hosting GitHub App インストール (一度きり)** で
成立し、Developer Connect が credential を内部保持する。terraform に必要なのは
**installation id だけ**。

1. **Firebase App Hosting GitHub App を組織にインストール** (ブラウザ・一度きり)。
   **robot / 共有アカウント**を使う。Firebase コンソールの App Hosting セットアップ、
   または Cloud コンソールの Developer Connect フローのどちらでも可。
2. **`app_installation_id` を取得** (組織レベル・再利用可・非機微):
   `gh api /orgs/<org>/installations --jq '.installations[] | "\(.id)\t\(.app_slug)"'`

これが唯一の一度きり手順。**コピーする OAuth token は無く**、Secret Manager に入れる
ものも無い。

</details>

---

## Per-environment setup

### 1. Provide the installation id (once per org, set as a repo Variable)

Pass `app_installation_id` via **Action B's `github_app_installation_id` input**, from a
repo **Variable** (`APPHOSTING_GITHUB_APP_INSTALLATION_ID`) — so the org-wide value is
not duplicated in every service's `settings.yml`. `make github-sync` derives and sets it
automatically.

```yaml
# consumer workflow (configure-platform.yml) calling Action B
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@...
  with:
    # ...
    github_app_installation_id: ${{ vars.APPHOSTING_GITHUB_APP_INSTALLATION_ID }}
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
  # github_connection は不要 (FIREBASE タイプは token/secret を使わない)。
  # app_installation_id は Action B input で渡す。connection 名/location を変えたい時のみ
  # github_connection: { connection_id: ..., location: ... } を任意で書く。
```

A backend is treated as **git-connected** when it has `branch` and/or `root_directory`
(and/or an explicit `repo`); a "bare backend" (none of these) keeps the legacy non-git
behavior. The clone_uri is normally **not** written — Action B derives
`https://github.com/<owner>/<service>.git` and injects it via `app_hosting_repo`
(override per-backend with `repo` only for a different repository).

<details><summary>Ja</summary>

### 1. installation id を渡す (組織で1回、repo Variable に)

`app_installation_id` は Action B の `github_app_installation_id` input (repo Variable
`APPHOSTING_GITHUB_APP_INSTALLATION_ID`) で渡す。`make github-sync` が自動導出・set する。

### 2. `settings.yml` を設定

`branch` / `root_directory` のいずれかがあれば git 連携 backend と判定される
(無ければ "bare backend")。clone_uri (`repo`) は通常書かず Action B が自動注入。
`github_connection` は不要 (FIREBASE タイプは token/secret 不使用)。

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
