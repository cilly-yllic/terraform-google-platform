# App Hosting (bare backend + Firebase CLI deploy)

This module creates a **bare** Firebase App Hosting backend (the backend resource + the
`firebase-app-hosting-compute` service account) and leaves the actual code deployment to
the **Firebase CLI** (`firebase deploy --only apphosting`, local source). Terraform owns
the backend "shell"; the CLI owns builds/rollouts.

## Why this split

- **No state pollution.** Terraform manages only the backend resource (+ compute SA). The
  CLI's builds / rollouts / traffic are a separate layer Terraform does not track, so
  `terraform plan` never drifts on them.
- **No GitHub connection, no browser auth.** Unlike the git-connection model, there is no
  Developer Connect connection to authorize. CI deploys with a service account.
- **CI permissions.** Terraform pre-creates the backend + compute SA (the per-env Terraform
  SA is Owner of the target project), so the CLI only performs *rollouts*. The CI SA is granted
  (automatically via `ci_service_account` when `app_hosting` is enabled):
  - `roles/firebaseapphosting.admin` — build / rollout / traffic
  - `roles/iam.serviceAccountUser` — act-as the compute SA
  - `roles/iam.serviceAccountCreator` — the Firebase CLI re-runs compute-SA "ensure (= create)"
    on every deploy even when the SA already exists ([firebase-tools#8840](https://github.com/firebase/firebase-tools/issues/8840));
    the create is swallowed as a 409 since Terraform creates the SA first, but the permission is still required
  - `roles/resourcemanager.projectIamAdmin` — the CLI's compute-SA ensure rewrites project IAM
    (`projects.setIamPolicy`) after SA creation

  > Note: `roles/resourcemanager.projectIamAdmin` is an Owner-class permission (can grant any role
  > to anyone). It is the concrete form of Firebase's "the first backend must be created by an
  > Owner" requirement, and is unavoidable when running CLI deploys from CI — meaning the CI SA is
  > effectively Owner-equivalent. This is an accepted trade-off.

<details><summary>Ja</summary>

terraform は **bare** な App Hosting backend (backend リソース + compute SA) を作り、実際の
コードのデプロイは **firebase CLI** (`firebase deploy --only apphosting`, local source) に任せる。

- **state 汚染なし**: terraform は backend (+ compute SA) のみ管理。CLI の build/rollout/traffic は
  別レイヤで追跡しないため drift しない。
- **GitHub 連携・ブラウザ認可 不要**。
- **CI 権限**: backend / compute SA を terraform (per-env SA=Owner) が先に作るので CLI は rollout だけ。
  `app_hosting` 有効時、CI SA (`ci_service_account`) に以下が自動付与される:
  - `roles/firebaseapphosting.admin` — build / rollout / traffic
  - `roles/iam.serviceAccountUser` — compute SA を act-as
  - `roles/iam.serviceAccountCreator` — firebase CLI は compute SA が既存でも毎回 ensure (= create) を
    試みるため必須 ([firebase-tools#8840](https://github.com/firebase/firebase-tools/issues/8840))。SA は
    terraform が先に作るので create は 409 で握り潰されるが、create 権限自体は要る
  - `roles/resourcemanager.projectIamAdmin` — CLI の compute SA ensure は SA 作成後にプロジェクト IAM を
    書き換える (`projects.setIamPolicy`) ため必須

  > 注: `roles/resourcemanager.projectIamAdmin` は Owner 級の強い権限 (任意ロールを誰にでも付与できる)。
  > Firebase の「最初の backend は Owner が作る」要件の実体であり、CLI デプロイを CI から回す以上避けられない
  > (= CI SA は実質 Owner 相当)。トレードオフとして許容している。

</details>

---

## settings.yml

```yaml
firebase_platform:
  apps:
    - name: task-tree-web-app
      type: web
  app_hosting:
    - backend_id: task-tree-web-app
      location: asia-east1
      app: task-tree-web-app          # 紐付ける web app (複数 web app があるため明示)
      # service_account / serving_locality は任意 (default: 共有 compute SA / GLOBAL_ACCESS)
```

`app_hosting` を指定すると terraform が:
- `google_firebase_app_hosting_backend`（backend の箱）
- `firebase-app-hosting-compute` SA + `roles/firebaseapphosting.computeRunner`
- API: `firebaseapphosting` / `run` / `cloudbuild` / `artifactregistry`
- CI SA (`ci_service_account`) に `firebaseapphosting.admin` + `iam.serviceAccountUser` + `iam.serviceAccountCreator` + `resourcemanager.projectIamAdmin`

を作成する。

## Runtime IAM（compute SA に追加権限を付与）

App Hosting backend は Cloud Run 上で **compute SA (`firebase-app-hosting-compute@<project>`)** として
実行される。backend の **runtime コードが他の GCP API を叩く** 場合、その権限を compute SA に
足す必要がある。`firebaseapphosting.computeRunner` だけでは backend 自身の実行に必要な最小権限しか
無く、アプリが使う API（Cloud Tasks / Pub/Sub / 他 SA の impersonate 等）はカバーされない。

代表例: backend が Cloud Tasks に task を enqueue する場合、enqueue に
`cloudtasks.tasks.create`（= `roles/cloudtasks.enqueuer`）が要る。これが無いと runtime で
`The principal ... lacks IAM permission "cloudtasks.tasks.create"` の 500 になる。

`app_hosting_compute_sa_roles` に追加 role を列挙すると、共有 compute SA に project-level で付与する:

```yaml
firebase_platform:
  app_hosting:
    - backend_id: web-app
      location: asia-northeast1
  # 共有 compute SA に追加付与する project-level role（追加分のみ。computeRunner は自動付与）
  app_hosting_compute_sa_roles:
    - roles/cloudtasks.enqueuer        # backend が Cloud Tasks に enqueue する場合
    # - roles/iam.serviceAccountUser   # enqueue 時に invoker SA を impersonate する場合 (下記注)
```

- **スコープ**: project-level 付与（`google_project_iam_member`, non-authoritative）。enqueue 先が
  複数キューに渡るケースを 1 binding でカバーでき、新キュー追加のたびの追記が不要。キュー単位の
  最小権限にしたい場合は本モジュール外で `google_cloud_tasks_queue_iam_member` を使う。
- **共有 SA が無い構成では no-op**: 全 backend に custom `service_account` を指定して共有 SA を
  作らない場合、付与対象が存在しないため何も起きない（custom SA 側で権限管理する）。

> **2 段目の権限に注意**: enqueue 成功後、Cloud Tasks がターゲット（recon 関数 / Cloud Run・Functions v2）
> を OIDC で invoke する。enqueue 時に指定する invoker SA に `roles/run.invoker`（や対象 SA の
> `iam.serviceAccountUser`）が別途必要になることがある。今回の `cloudtasks.tasks.create` は 1 段目なので、
> まず `roles/cloudtasks.enqueuer` で enqueue の 500 は解消する。invoke 段で PERMISSION_DENIED が出たら
> invoker SA 側の `run.invoker` を追加確認すること。

## デプロイ（CI / firebase CLI）

サービス repo の `firebase.json` に App Hosting 設定を置き、CI で deploy する:

```jsonc
// firebase.json
{
  "apphosting": {
    "backendId": "task-tree-web-app",
    "rootDir": "./apps/task-tree/web-app",
    "alwaysDeployFromSource": true
  }
}
```

```yaml
# deploy workflow (WIF で ci-deploy SA を impersonate)
- uses: google-github-actions/auth@v2
  with:
    project_id: <project>
    workload_identity_provider: ${{ env.WIF_PROVIDER }}
    service_account: ci-deploy@<project>.iam.gserviceaccount.com
- run: pnpm exec firebase deploy --only apphosting --project <env> --non-interactive --force
```

`firebase deploy --only apphosting` は local source を Cloud Build に upload してビルドし、
Cloud Run + Artifact Registry にロールアウトする。backend / compute SA は terraform 作成済みなので
`serviceAccounts.create` は不要。

> 注: firebase-tools には「Cloud Build 失敗でも exit 0」になる既知バグ
> ([#9973](https://github.com/firebase/firebase-tools/issues/9973)) がある。CI で確実に失敗検知
> したい場合は rollout/build の状態を別途確認するとよい。

## 前提
- 対象プロジェクトが **Blaze プラン**（App Hosting 要件）。
- backend は terraform が **Owner（per-env SA）**で初回作成する（"first backend は Owner が作る"
  という App Hosting の制約を満たす）。
