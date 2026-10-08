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

## Unreleased (v1.1.0)

### Provider support
- `hashicorp/google` / `hashicorp/google-beta`: the upper bound is raised from `< 8.0` to `< 9.0` (lower bound `>= 6.0` unchanged). None of the resources used by this module are affected by the [v8 breaking changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/version_8_upgrade).
  - **Calling the module directly**: your own lock file / version constraint decides. Run `terraform init -upgrade` to move to 8.x.
  - **Via the dispatch Action**: no lock file is uploaded, so the first run after updating picks the **latest 8.x automatically**. Provider 8.x rewrites the state schema, so going back to 7.x requires restoring state. To stay on 7.x, pin `module_version` to a release before this one. We recommend running a plan once and confirming it is a no-op.

### Features
- `storage.buckets[].cors`: CORS rules for additional buckets (same names/semantics as the `google_storage_bucket` `cors` block). Omitting it produces no diff.

<details><summary>Ja</summary>

- `hashicorp/google` / `google-beta` の上限を `< 8.0` → `< 9.0` に引き上げ (下限 `>= 6.0` は据え置き)。本モジュールが使うリソースに v8 の破壊的変更の該当はない。
  - **module を直接呼ぶ場合**: 利用側の lock file / version 制約に従う。8.x に上げるなら `terraform init -upgrade`。
  - **dispatch Action 経由の場合**: lock file を upload しないため、更新後の初回 run で **8.x の最新に自動で上がる**。8.x は state schema を書き換えるため 7.x へ戻すには state の復元が必要。7.x に留めたい場合は `module_version` を本リリースより前に pin する。一度 plan を流して no-op を確認することを推奨。
- `storage.buckets[].cors`: 追加 bucket に CORS ルールを指定可能に (`google_storage_bucket` の `cors` ブロックと同名・同義)。省略時は差分なし。

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
