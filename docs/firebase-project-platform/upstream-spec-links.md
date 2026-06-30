# Upstream documentation links

An index of the [`docs/project-bootstrap/`](../project-bootstrap/) design documents that underpin this repository.

<details><summary>Ja</summary>

本リポジトリの設計・実装の根拠となる [`docs/project-bootstrap/`](../project-bootstrap/) 設計ドキュメントへの索引。

</details>

---

## Upstream document list

### architecture.md

[`docs/project-bootstrap/architecture.md`](../project-bootstrap/architecture.md)

An overarching architecture document describing the full Terraform execution platform (bootstrap → project-factory → firebase-project-platform → service workspaces), Phase 1/Phase 2 provisioning strategies, Workspace structure, and Apply policies.

| Mapping in this repo |
|---|
| Referenced throughout; see [architecture.md](./architecture.md) |

<details><summary>Ja</summary>

全体アーキテクチャドキュメント。Terraform 実行基盤の全レイヤー (bootstrap → project-factory → firebase-project-platform → service workspaces)、Phase 1/Phase 2 の provisioning 戦略、Workspace 構造、Apply 方針を記述している。

対応: リポジトリ全体で参照; [architecture.md](./architecture.md) を参照

</details>

---

### related-components.md

[`docs/project-bootstrap/related-components.md`](../project-bootstrap/related-components.md)

Describes related components including this repository (terraform-google-platform), infra-orchestrator, Cloud Run router, and the public GitHub Actions.

| Mapping in this repo |
|---|
| `cloud-run-router/`, `actions/dispatch/` |

<details><summary>Ja</summary>

本リポジトリ (terraform-google-platform) を含む関連コンポーネント、infra-orchestrator、Cloud Run router、public GitHub Actions の概要と責務分離を記述している。

対応するコード: `cloud-run-router/`, `actions/dispatch-firebase-platform/`

</details>

---

### design/iam-policy.md

[`docs/project-bootstrap/design/iam-policy.md`](../project-bootstrap/design/iam-policy.md)

IAM role assignment design rationale: which roles are granted and why, which roles are intentionally withheld, and under what conditions they should be re-granted.

<details><summary>Ja</summary>

IAM role 付与の設計根拠: どの role をなぜ付与するか、意図的に付与しない role と再付与条件。

</details>

---

### design/wif-attribute-mapping.md

[`docs/project-bootstrap/design/wif-attribute-mapping.md`](../project-bootstrap/design/wif-attribute-mapping.md)

WIF Attribute Mapping / Attribute Condition details for the Workload Identity Provider.

<details><summary>Ja</summary>

Workload Identity Provider の Attribute Mapping / Attribute Condition の詳細。

</details>

---

## Internal documentation

| Document | Content |
|----------|---------|
| [architecture.md](./architecture.md) | Position of this module, layer separation, bundled reference implementations |
| [variables-reference.md](./variables-reference.md) | Nested structures and defaults for feature variables |
| [api-auto-enablement.md](./api-auto-enablement.md) | Feature → auto-enabled GCP API mapping |
| [console-access.md](./console-access.md) | Firebase Console / GCP IAM access design |
| [service-accounts.md](./service-accounts.md) | CI SA auto-role logic and additional SA operations |
| [upgrade-guide.md](./upgrade-guide.md) | Breaking changes per Registry version |

<details><summary>Ja</summary>

| ドキュメント | 内容 |
|----------|---------|
| [architecture.md](./architecture.md) | 本モジュールの位置づけ / レイヤー分離 / reference 実装との責務分離 |
| [variables-reference.md](./variables-reference.md) | 機能変数のネスト構造とデフォルト値 |
| [api-auto-enablement.md](./api-auto-enablement.md) | 機能 → 自動有効化 GCP API の対応表 |
| [console-access.md](./console-access.md) | Firebase Console / GCP IAM の権限設計 |
| [service-accounts.md](./service-accounts.md) | CI SA の自動 role 決定ロジックと追加 SA の運用 |
| [upgrade-guide.md](./upgrade-guide.md) | Registry バージョン間の breaking change |

</details>
