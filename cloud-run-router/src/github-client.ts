/**
 * GitHub App 認証と repository_dispatch 発火クライアント。
 *
 * 認証フロー (GitHub App の installation token 取得):
 *   1. App private key で JWT を作成 (App 全体の認証情報)
 *   2. その JWT で対象 owner/repo の installation を引く
 *   3. installation ID から「対象 repo のみ / 書き込み権限のみ」に絞った
 *      access token を発行 (短命; 1 時間で失効)
 *   4. その token で repository_dispatch API を叩く
 *
 * なぜ installation token を毎回取り直すのか:
 *   - access token は 1 時間で失効する
 *   - Cloud Run のインスタンスはスケール in/out で頻繁に入れ替わる
 *   - リクエスト頻度が低い (Notification 受信ごと) ので keep-alive キャッシュの
 *     恩恵は薄い
 *   - キャッシュ実装を持つと token 漏洩時のローテートが面倒
 *   よって毎回取り直す。1 dispatch あたり GitHub API を 3 回叩くが、レイテンシ
 *   は許容範囲 (~数百 ms)。
 *
 * 最小権限の原則:
 *   - repositories: [repo] で対象 repo を 1 件に絞る
 *   - permissions: { contents: write } のみ
 *   これにより万一 token が漏れても被害範囲が限定される。
 *
 * @see https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app
 * @see https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event
 */
import { createPrivateKey, createSign } from 'node:crypto'

/** GitHub API 呼び出しの全体 timeout */
const FETCH_TIMEOUT_MS = 30_000

/** エラーログに載せる GitHub レスポンスの最大長 */
const MAX_ERROR_BODY_LENGTH = 200

/** GitHub API は User-Agent ヘッダを要求する。本サービスの識別子 */
const USER_AGENT = 'cloud-run-router/1.0'

interface JwtClaims {
  /** issuer = GitHub App ID */
  iss: string
  /** issued at (epoch seconds) */
  iat: number
  /** expiration (epoch seconds, iat から最長 10 分) */
  exp: number
}

/**
 * Base64URL エンコード (RFC 7515 / JWT の各セグメントで使う形式)。
 * Node 16+ の Buffer は 'base64url' エンコーディングを native サポート
 * しているため、padding (=) 除去や URL-safe 文字変換を自前で行う必要なし。
 */
const base64url = (data: Buffer | string): string => {
  const buf = typeof data === 'string' ? Buffer.from(data) : data
  return buf.toString('base64url')
}

/**
 * GitHub App の認証 JWT を作成する。
 * GitHub の仕様で:
 *   - alg は RS256 (RSA-SHA256) 必須
 *   - iss は App ID
 *   - exp は iat から最長 10 分 (それを超えると 401)
 *   - iat はサーバ間のクロックずれ吸収のため少し過去 (-60s) にしておくのが推奨
 *
 * @see https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
 */
const createJwt = (claims: JwtClaims, privateKeyPem: string): string => {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = base64url(JSON.stringify(claims))
  const unsigned = `${header}.${payload}`

  // PEM 文字列から PrivateKeyObject にロードして RSA-SHA256 で署名する。
  const key = createPrivateKey(privateKeyPem)
  const signer = createSign('RSA-SHA256')
  signer.update(unsigned)
  const signature = signer.sign(key)

  return `${unsigned}.${base64url(signature)}`
}

/**
 * 対象 owner/repo に紐づく installation の access token を取得する。
 *
 * App は複数の org / user にインストール可能なので、対象 repo にどの
 * installation 経由でアクセスするかをまず引く必要がある (step 1)。
 * その installation に対して「scope を絞った access token」を発行する (step 2)。
 *
 * step 2 のリクエストボディで repo と permission を最小化することで、
 * 万一の token 漏洩時の被害範囲を抑えている (least privilege)。
 */
const getInstallationToken = async (
  appId: string,
  privateKeyPem: string,
  owner: string,
  repo: string
): Promise<string> => {
  // App JWT の作成。
  // iat を -60s にしてクロックずれを吸収、exp は GitHub の上限 10 分 (600s) に設定。
  // 単発呼び出しなので long-lived にする必要はないが、ローカル時計が遅れている
  // 環境を想定すると 5 分以上は欲しい。
  const now = Math.floor(Date.now() / 1000)
  const jwt = createJwt({ iss: appId, iat: now - 60, exp: now + 600 }, privateKeyPem)

  // Step 1: 対象 repo に対応する installation を引く。
  // GitHub App がその repo にインストールされていない場合は 404 が返る
  // (= 設定漏れなので明示的なエラーで落とす)。
  const installRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/installation`, {
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': USER_AGENT,
      'X-GitHub-Api-Version': '2022-11-28',
    },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })
  if (!installRes.ok) {
    const body = await installRes.text()
    throw new Error(
      `GitHub App installation lookup failed for ${owner}/${repo}: ${installRes.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`
    )
  }
  const installData = (await installRes.json()) as { id?: number }
  if (typeof installData.id !== 'number') {
    throw new Error(`GitHub App installation response missing 'id' for ${owner}/${repo}`)
  }

  // Step 2: installation から repo と permission を絞った access token を発行。
  // - repositories: [repo]            → 対象 repo 1 件にだけ有効
  // - permissions: { contents: write } → repository_dispatch に必要な最小権限
  //   (dispatch は contents: write で発火できる; 詳細は GitHub docs 参照)
  const tokenRes = await fetch(`https://api.github.com/app/installations/${installData.id}/access_tokens`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': USER_AGENT,
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({
      repositories: [repo],
      permissions: { contents: 'write' },
    }),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })
  if (!tokenRes.ok) {
    const body = await tokenRes.text()
    throw new Error(
      `GitHub installation token creation failed: ${tokenRes.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`
    )
  }
  const tokenData = (await tokenRes.json()) as { token?: string }
  if (!tokenData.token) {
    throw new Error(`GitHub installation token response missing 'token' for ${owner}/${repo}`)
  }
  return tokenData.token
}

/**
 * Action B (caller workflow) が受け取る client_payload の shape。
 *
 * Action B は `environments` または `labels` のどちらかを使って
 * settings.yml に対する env 解決を行う:
 *   - environments を直接渡す → A が解決済みの env リストをそのまま使う
 *   - labels を渡す           → B が settings.yml を読み直して再解決する
 * 両者の使い分けは README "Dispatch payload shape" セクション参照。
 *
 * 前提 (wire 表現): この型は cloud-run-router 内部の論理表現。実際に
 * client_payload として送出する際は repositoryDispatch() が environments /
 * labels を **compact JSON 文字列** にシリアライズする (toWireClientPayload 参照)。
 * 受信側 (Action B) は `${{ github.event.client_payload.environments }}` を
 * toJSON() 無しの直接参照で単一行 '["dev-001"]' として取得できる。
 */
export interface DispatchPayload {
  service: string

  /** Action A が今回 Run で実際に処理対象とした env キー */
  environments: string[]

  /**
   * Action A 起動時の input labels (RegExp 文字列)。
   * - A が `environment` 単数で呼ばれていた場合は空配列
   * - caller workflow は `labels` を B にそのまま渡せば B が再解決可能
   */
  labels: string[]

  run_id: string
  workspace_name: string
  source_repo: string
}

/**
 * DispatchPayload を repository_dispatch の client_payload (wire 表現) に変換する。
 *
 * WHY: GitHub Actions の `toJSON()` は配列を 2-space indent + 改行で pretty-print
 * する。受信側 workflow が `${{ toJSON(client_payload.environments) }}` の結果を
 * `echo "environments=${val}" >> "$GITHUB_OUTPUT"` で書くと値が複数行になり、
 * GITHUB_OUTPUT の `key=value` 形式 (単一行のみ許容) に違反して
 * `Invalid format '  "dev-001"'` で落ちる。
 *
 * そこで environments / labels を送出時点で compact JSON 文字列に固めておく。
 * これにより受信側は toJSON() 不要の直接参照で単一行値を得られ、
 * GITHUB_OUTPUT への書き込みも trim も不要になる。
 *
 * 周辺仕様: 受信側 (Action B) の `environments` / `labels` input は
 *   actions/dispatch-firebase-platform の parseEnvironmentsInput / parseLabelsInput
 * が JSON 配列文字列として JSON.parse する。compact 文字列はそのまま parse 可能。
 */
export const toWireClientPayload = (payload: DispatchPayload): Record<string, unknown> => ({
  ...payload,
  environments: JSON.stringify(payload.environments),
  labels: JSON.stringify(payload.labels),
})

/**
 * 対象 repo に repository_dispatch イベントを発火する。
 *
 * target_repo の検証:
 *   - "owner/repo" 形式以外は throw (テンプレートインジェクション防止)
 *   - ".." を含む値は path traversal 試行とみなして throw
 *     (GitHub API URL に組み込まれるため、相対パス記法を防ぐ)
 *
 * リトライ方針:
 *   この関数自体はリトライしない。失敗時に呼び出し元 (handleNotification 経由
 *   webhook ハンドラ) で throw が伝搬して 500 になり、TFC 側の Notification
 *   再送に任せる。GitHub API への過剰なリトライを内部で持つよりも、
 *   TFC のリトライ仕組みに乗ったほうが運用がシンプル。
 */
export const repositoryDispatch = async (
  appId: string,
  privateKeyPem: string,
  targetRepo: string,
  eventType: string,
  payload: DispatchPayload
): Promise<void> => {
  // "owner/repo" 形式の素朴な検証。
  // 厳格な正規表現にしないのは、GitHub の許容文字を変に絞ると将来の
  // 命名仕様変更に追従しづらくなるため。最低限 "/" で 2 セグメントに割れて
  // 双方が非空、かつ path traversal が混ざらないことだけを保証する。
  const parts = targetRepo.split('/')
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error(`Invalid target_repo format: "${targetRepo}" (expected "owner/repo")`)
  }
  const [owner, repo] = parts
  if (owner.includes('..') || repo.includes('..')) {
    throw new Error(`Invalid target_repo format: "${targetRepo}" (expected "owner/repo", no path traversal)`)
  }

  // installation token を取って即 dispatch。token はそのまま捨てる
  // (1 時間で自然失効、明示的な revoke も特に必要なし)。
  const token = await getInstallationToken(appId, privateKeyPem, owner, repo)

  const res = await fetch(`https://api.github.com/repos/${owner}/${repo}/dispatches`, {
    method: 'POST',
    headers: {
      Authorization: `token ${token}`,
      Accept: 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': USER_AGENT,
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({
      event_type: eventType,
      client_payload: toWireClientPayload(payload),
    }),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })

  // 204 No Content が正常応答。それ以外はステータスを含めて throw し、
  // 上位の onError ハンドラから 500 として返す。
  if (!res.ok) {
    const body = await res.text()
    throw new Error(
      `repository_dispatch failed for ${targetRepo}: ${res.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`
    )
  }
}
