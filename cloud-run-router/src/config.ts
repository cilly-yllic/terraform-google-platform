/**
 * 環境変数からの Config 構築と検証。
 *
 * 本モジュールの方針は **fail fast**:
 *   - 必須 env が欠けている / 値が不正なら起動時に throw する
 *   - 起動後にリクエストを受けてから検証するより、Cloud Run の再起動ループで
 *     設定ミスがログに即可視化された方が安全
 *
 * Secret Manager に保存することを想定している値:
 *   - TFC_NOTIFICATION_SECRET  (TFC との HMAC 共有 secret)
 *   - GITHUB_APP_PRIVATE_KEY   (GitHub App private key PEM)
 *   - TFC_API_TOKEN            (Option A 使用時のみ)
 * これらは Cloud Run のデプロイ時に --set-secrets で env として注入する。
 *
 * @see ../README.md  — 各 env 変数の意味と Secret 設計の詳細
 */

export interface Config {
  /** HTTP 待受ポート (Cloud Run が `PORT` 環境変数で指定してくる) */
  port: number

  /** TFC Notification の HMAC-SHA512 共有 secret */
  tfcNotificationSecret: string

  /**
   * TFC API token (Personal / Team token)。
   * metadataSource が "run_variables" / "both" の場合のみ必須。
   * "run_message" 単独運用時は使用しないので undefined を許容する。
   */
  tfcApiToken: string | undefined

  /** TFC API base URL (Terraform Enterprise の場合は自社 URL に上書き) */
  tfcApiBaseUrl: string

  /** GitHub App ID (numeric string) */
  githubAppId: string

  /** GitHub App private key (PEM 形式の文字列) */
  githubAppPrivateKey: string

  /**
   * project-factory stage の workspace 名にマッチさせる正規表現。
   * named capture group `service` を含む必要がある。
   * default: ^project-factory-(?<service>.+)$
   *
   * `service` は GitHub repository_dispatch の payload と紐づく一意キー。
   */
  projectFactoryPattern: RegExp

  /**
   * terminal (firebase-platform) stage の workspace 名にマッチさせる正規表現。
   * named capture groups `service` と `env` を持つ必要がある。
   * default: ^(?<service>.+)-(?<env>[^-]+)$
   * (env = 最後のハイフン区切りセグメント、service = 残り)
   *
   * このパターンにマッチした Run は dispatch を発火せず、no-op としてログだけ残す
   * (パイプラインの末端なので、これ以降にチェーンするものが無い)。
   */
  terminalPattern: RegExp

  /** repository_dispatch の event_type 文字列 */
  dispatchEventType: string

  /**
   * Run metadata (service / environments / source_repo) の取得方式。
   *
   * - "run_message"   : run_message を JSON として直接 parse (Option B)
   *                     Action A/B が新 shape を emit する前提なので、
   *                     Phase 2 chaining の標準パス
   * - "run_variables" : TFC API で workspace 変数を引く (Option A)
   *                     run_message が空の旧 Action 対応や migration 期間用
   * - "both"          : run_message を先に試し、失敗時に TFC API へフォールバック
   *                     (default。本番は通常これで運用)
   *
   * @see ./tfc-client.ts  — fetchRunMetadata (Option A) / parseRunMessage (Option B)
   */
  metadataSource: 'run_message' | 'run_variables' | 'both'
}

const VALID_METADATA_SOURCES = ['run_message', 'run_variables', 'both'] as const

/**
 * 必須環境変数を取り出す。未設定/空文字どちらも fail させる。
 * "" を許容してしまうと downstream で意味不明な認証失敗等を引き起こすため、
 * 空文字も明示的に reject している。
 */
const requiredEnv = (name: string): string => {
  const v = process.env[name]
  if (v === undefined || v === '') {
    throw new Error(
      v === undefined
        ? `Required environment variable ${name} is not set`
        : `Required environment variable ${name} is empty`
    )
  }
  return v
}

const validateMetadataSource = (value: string): Config['metadataSource'] => {
  if (!VALID_METADATA_SOURCES.includes(value as Config['metadataSource'])) {
    throw new Error(`Invalid METADATA_SOURCE "${value}". Must be one of: ${VALID_METADATA_SOURCES.join(', ')}`)
  }
  return value as Config['metadataSource']
}

/**
 * env 経由で渡された正規表現文字列をコンパイル。
 * 不正な regex を起動時に検出して落とす目的 (リクエスト時に SyntaxError が
 * 出ると 500 で隠れてしまい、デプロイ時の検知が遅れるため)。
 */
const validateRegex = (envName: string, pattern: string): RegExp => {
  try {
    return new RegExp(pattern)
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    throw new Error(`Invalid regex in ${envName}: "${pattern}" — ${msg}`)
  }
}

const validatePort = (value: string): number => {
  const port = Number(value)
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error(`Invalid PORT "${value}". Must be an integer between 0 and 65535`)
  }
  return port
}

export const loadConfig = (): Config => {
  // パターン系は default を持たせて optional 扱い。
  // 利用組織がデフォルトの workspace 命名規約を踏襲していればそのまま動く。
  const pfPattern = process.env['WORKSPACE_NAME_PATTERN'] ?? '^project-factory-(?<service>.+)$'
  const termPattern = process.env['TERMINAL_WORKSPACE_PATTERN'] ?? '^(?<service>.+)-(?<env>[^-]+)$'

  const metadataSource = validateMetadataSource(process.env['METADATA_SOURCE'] ?? 'both')
  const tfcApiToken = process.env['TFC_API_TOKEN']

  // run_variables / both は TFC API への HTTP 呼び出しが必要なので、
  // token が無いと metadata 解決自体が必ず失敗する。先に弾いておく。
  if ((metadataSource === 'run_variables' || metadataSource === 'both') && !tfcApiToken) {
    throw new Error(`TFC_API_TOKEN is required when METADATA_SOURCE is "${metadataSource}"`)
  }

  return {
    port: validatePort(process.env['PORT'] ?? '8080'),
    tfcNotificationSecret: requiredEnv('TFC_NOTIFICATION_SECRET'),
    tfcApiToken,
    tfcApiBaseUrl: process.env['TFC_API_BASE_URL'] ?? 'https://app.terraform.io',
    githubAppId: requiredEnv('GITHUB_APP_ID'),
    githubAppPrivateKey: requiredEnv('GITHUB_APP_PRIVATE_KEY'),
    projectFactoryPattern: validateRegex('WORKSPACE_NAME_PATTERN', pfPattern),
    terminalPattern: validateRegex('TERMINAL_WORKSPACE_PATTERN', termPattern),
    dispatchEventType: process.env['DISPATCH_EVENT_TYPE'] ?? 'firebase_platform_requested',
    metadataSource,
  }
}
