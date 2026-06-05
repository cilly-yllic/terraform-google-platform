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
