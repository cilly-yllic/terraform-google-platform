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
- **Low CI permissions, no Owner.** Because Terraform pre-creates the backend + compute SA
  (the per-env Terraform SA is Owner of the target project), the CLI only performs
  *rollouts* — which need just `roles/firebaseapphosting.admin` + `roles/iam.serviceAccountUser`
  on the CI SA (granted automatically via `ci_service_account`). The CLI does **not** need
  `iam.serviceAccounts.create` (that's only for first-time backend/compute-SA creation,
  which Terraform handles).

<details><summary>Ja</summary>

terraform は **bare** な App Hosting backend (backend リソース + compute SA) を作り、実際の
コードのデプロイは **firebase CLI** (`firebase deploy --only apphosting`, local source) に任せる。

- **state 汚染なし**: terraform は backend (+ compute SA) のみ管理。CLI の build/rollout/traffic は
  別レイヤで追跡しないため drift しない。
- **GitHub 連携・ブラウザ認可 不要**。
- **CI 権限は最小・Owner 不要**: backend / compute SA を terraform (per-env SA=Owner) が先に作るので、
  CLI は rollout だけ → CI SA は `firebaseapphosting.admin` + `iam.serviceAccountUser` のみで可。
  `iam.serviceAccounts.create` は初回 backend 作成時だけ必要で、それは terraform が担う。

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
- CI SA (`ci_service_account`) に `firebaseapphosting.admin` + `iam.serviceAccountUser`

を作成する。

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
