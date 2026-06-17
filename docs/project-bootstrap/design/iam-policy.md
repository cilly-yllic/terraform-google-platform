# IAM Policy Design

bootstrap script (`scripts/bootstrap.sh`) および `project-bootstrap` module が付与する IAM role の設計根拠と、意図的に付与しない role の例外条件をまとめる。

設計の中心方針:

1. **per-project SA**: env ごとの terraform SA (`terraform-{service}-{env}`) は **作成したターゲット project の中**に作る (infra には作らない)。quota / 課金 / 権限 / ライフサイクルがその project に閉じ、infra に `project 数 × env 数` 分の SA が溜まる問題 (GCP は 1 project あたり SA 100 個上限) を避ける。
2. **強権 SA の利用主体を絞る**: Factory SA (`terraform-project-factory`) は org/folder レベルの project 作成・IAM 権限を持つ強権 SA。これを impersonate できるのは **factory workspace だけ**に限定する。
3. **graceful degradation**: 本リポジトリは公開モジュールのため、GCP folder を使える環境ではより強く封じ込め、folder が無い環境でも一定の security floor を確保する。

---

## 1. bootstrap script が付与する role (caller = org/folder admin が実行)

### Factory SA `terraform-project-factory` — Organization または Folder レベル

| Role | 理由 | スコープの考え方 |
|------|------|------------------|
| `roles/resourcemanager.projectCreator` | サービス用 GCP Project を作成する | **folder 推奨**。`FOLDER_ID` 設定時は folder に付与し、作成可能範囲をその folder 内に限定。`ORGANIZATION_ID` のみの場合は org 全体 (floor) |
| `roles/resourcemanager.projectIamAdmin` | 作成した Project の per-env SA に owner を付与する | 同上。folder 限定が望ましい |

> **folder vs org**: `projectCreator` は性質上 org か folder にしか付与できない (まだ存在しない project には付与できないため)。folder を用意できる環境では folder を指定し、Factory SA が触れる範囲をその folder 内に封じ込めること。bootstrap は `FOLDER_NAME` (display name) から folder を find-or-create して `FOLDER_ID` を解決できる (`scripts/bootstrap/_commands/ensure_folder.sh`)。folder mode では folder が org に優先する (`grant_iam.sh`)。folder 無し (org 直下) でも動くが、Factory SA の到達範囲が org 全体になる点を許容する判断が必要。いずれの場合も「Factory SA を *誰が* 使えるか」は §2 の `terraform_workspace_kind=factory` で factory workspace のみに絞られている。
>
> **重要 (folder mode の linkage)**: folder スコープの grant はその folder 内の project にしか効かない。よって**サービス project もその folder 配下に作成する**必要がある。`dispatch-project-bootstrap` action の `parent_folder_id` を bootstrap の `FOLDER_ID` と一致させること (別 folder / org 直下に作るとサービス project に対し Factory SA の `projectIamAdmin` が届かず、per-env SA への owner 付与が失敗する)。

### Factory SA — Billing Account レベル

| Role | 理由 |
|------|------|
| `roles/billing.user` | Project に Billing Account を紐付ける |

`ORGANIZATION_ID` 設定時は org-level の `billing.user` も付与する (org 所有の全 billing account に inherit され、新 billing account 追加時の手動 grant が不要になる利便性のため)。最小権限を優先する場合は org-level を外し、`make grant-billing BILLING=<id>` で per-account 付与する。

### Factory SA — infra-bootstrap Project レベル

**付与なし (footprint ゼロ)。**

Factory SA が `project-bootstrap` module 実行時に行う操作はすべて「作成したターゲット project の中」に閉じる (project 作成 / API 有効化 / per-env SA 作成 / owner 付与 / per-env SA への WIF binding)。これらは上記 org/folder ロールと、作成 project への owner で充足する。

かつて必要だった以下は不要になった:

- `roles/iam.serviceAccountAdmin` — 旧設計は per-env SA を infra に作っていたため必要だった。per-project SA 化により SA はターゲット project 内に作るので不要
- `roles/iam.workloadIdentityPoolAdmin` — WIF pool/provider は bootstrap script (人間) が管理し、Factory SA は pool 名を**参照するだけ**で作成・変更しない
- infra project の project number 読み取り (`data.google_project`) — action が渡す `bootstrap_project_number` 変数に置き換えたため、read role すら不要

### Cloud Run Router 用 (任意 / `ENABLE_CLOUD_RUN_DEPLOY_SETUP=true` 時)

Deploy SA (`gcloud run deploy` を実行する GitHub Actions の identity):

| 付与先 | Role | 理由 |
|--------|------|------|
| infra project | `roles/run.admin` | Cloud Run deploy + `allUsers → run.invoker` の setIamPolicy (`run.developer` には含まれない) |
| infra project | `roles/artifactregistry.writer` | image push |
| infra project | `roles/cloudbuild.builds.editor` | `gcloud builds submit` |
| infra project | `roles/storage.admin` | Cloud Build の source upload bucket |
| infra project | `roles/secretmanager.secretVersionAdder` | HMAC / GitHub App key の新 version push |
| **runtime SA リソース** | `roles/iam.serviceAccountUser` | `--service-account=<runtime>` 指定 |
| **runtime SA リソース** | `roles/iam.serviceAccountTokenCreator` | runtime SA の token 発行。**runtime SA 限定** (project レベルにしない) |
| Cloud Build runner SA | `roles/iam.serviceAccountUser` | build job を runner SA として起動 |

Runtime SA (Cloud Run service の実行 identity):

| 付与先 | Role | 理由 |
|--------|------|------|
| infra project | `roles/secretmanager.secretAccessor` | runtime での secret 読み取り |

> **tokenCreator を runtime SA 限定にする理由**: project レベルに付けると Deploy SA が infra 内の**全 SA (Factory SA 含む) の token を発行**でき、GitHub 発火の Deploy SA から Factory SA へ成り代わる経路が生まれる。対象を runtime SA だけに絞ってこの横移動を遮断する。

---

## 2. bootstrap script が付与する WIF binding

### Factory SA の impersonation — factory workspace 限定

```text
roles/iam.workloadIdentityUser
member: principalSet://.../attribute.terraform_workspace_kind/factory
```

`terraform_workspace_kind` は WIF provider の attribute mapping で **workspace 名から導出する派生属性** (workspace 名が `${FACTORY_WORKSPACE_PREFIX}` = default `project-factory-` で始まれば `factory`、それ以外は `service`)。

これにより Factory SA を impersonate できるのは `project-factory-*` workspace だけになり、firebase 設定用の `{service}-{env}` workspace や実験用 workspace からの成り代わりを構造的に塞ぐ。provider 側の attribute-condition (org 一致) が外側のゲートとして残るので、実効条件は「**自 org かつ factory workspace**」。

詳細: [wif-attribute-mapping.md](./wif-attribute-mapping.md)

### Deploy SA の impersonation (任意) — repo 限定

```text
roles/iam.workloadIdentityUser
member: principalSet://.../attribute.repository/{GITHUB_REPOSITORY}
```

---

## 3. project-bootstrap module が付与する role (実行主体 = Factory SA)

### ターゲット Project の最小 API 有効化

per-env SA をターゲット project 内に作るために必要:

- `iam.googleapis.com` (SA 作成に必須)
- `serviceusage.googleapis.com` / `cloudresourcemanager.googleapis.com` (以降の API 操作の前提)

firebase 等その他 API は後段 `firebase-project-platform` 側で有効化する (二重管理を避け、ここは「SA を作るための最小限」に留める)。

### per-env SA `terraform-{service}-{env}` — ターゲット Project レベル

| Role | 理由 |
|------|------|
| `roles/owner` | この SA はそのターゲット project 専用 (1 project = 1 service-env) なので owner で閉じる |

> **owner にした理由**: `firebase-project-platform` module は `google_firebase_project` / Firestore / Storage / Hosting 等を作成し、これには `firebase.admin` 等が必要。個別列挙だと機能追加のたびに権限漏れを起こす。project 単位で隔離されている前提なので owner が素直 (旧 `projectIamAdmin` / `serviceUsageAdmin` / `serviceAccountAdmin` の 3 ロールは owner に内包される)。最小権限を厳格化したい場合は curated set への移行余地あり。

### per-env SA の impersonation (WIF binding) — workspace 限定

```text
roles/iam.workloadIdentityUser
member: principalSet://.../attribute.terraform_workspace/{tfc_workspace_name}
```

`{tfc_workspace_name}` は firebase-platform 側の workspace (`{service}-{env}`)。TFC Workspace から per-env SA を **直接 WIF** で impersonate する (二段 impersonation は使わない)。

---

## 4. セキュリティモデル要約

| 軸 | 制御 | 効果 |
|----|------|------|
| **WHO** (誰が強権 SA を使えるか) | `terraform_workspace_kind=factory` (全 consumer 共通の floor) | factory workspace のみが Factory SA を impersonate 可。無関係 workspace を遮断 |
| **WHAT** (強権 SA が触れる範囲) | folder スコープ grant (folder がある環境のみ) | Factory SA の到達範囲を folder 内に封じ込め |
| **per-env の隔離** | SA をターゲット project 内に作成 + owner | quota / 課金 / 権限がその project に閉じる |

folder 無しの floor: Factory SA の到達は org 全体になるが、WHO は factory workspace に限定済み。残留リスクは「compromise された factory workspace が org 全体に影響しうる」ことだが、factory workspace は数が少なく action 経由でのみ作成される統制下にある。folder ありならこのリスクも folder 内に封じ込められる。

---

## 5. 意図的に付与しない role と再付与条件

### Factory SA: infra project レベルのロール全般

**不付与の理由:** §1 の通り、Factory SA の操作はターゲット project 内に閉じ、project number も変数で渡すため infra への standing role は一切不要。

**再付与が必要になる条件:** project-bootstrap module が infra project 自体のリソースを操作する設計に変わった場合。その場合も最小スコープ (必要な read/write role のみ) を infra project レベルで付与する。

### per-env SA → 二段 impersonation 用の token 系ロール

**不付与の理由:** TFC → 各 SA への impersonation は直接 WIF で行い、二段 impersonation 経路を持たない。

**再付与時のスコープ:** 直接 WIF が使えない事情が生じた場合のみ、対象 SA リソース限定で付与 (project レベルにはしない)。設計レビュー必須。
