import { createPrivateKey, createSign } from "node:crypto";

const FETCH_TIMEOUT_MS = 30_000;
const MAX_ERROR_BODY_LENGTH = 200;
const USER_AGENT = "cloud-run-router/1.0";

interface JwtClaims {
  iss: string;
  iat: number;
  exp: number;
}

function base64url(data: Buffer | string): string {
  const buf = typeof data === "string" ? Buffer.from(data) : data;
  return buf.toString("base64url");
}

function createJwt(claims: JwtClaims, privateKeyPem: string): string {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify(claims));
  const unsigned = `${header}.${payload}`;

  const key = createPrivateKey(privateKeyPem);
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  const signature = signer.sign(key);

  return `${unsigned}.${base64url(signature)}`;
}

/**
 * Generate a GitHub App installation token.
 *
 * 1. Create a JWT signed with the App private key.
 * 2. Find the installation for `owner`.
 * 3. Create an installation access token scoped to the target repo.
 */
async function getInstallationToken(
  appId: string,
  privateKeyPem: string,
  owner: string,
  repo: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwt = createJwt(
    { iss: appId, iat: now - 60, exp: now + 600 },
    privateKeyPem,
  );

  // Find installation for the owner
  const installRes = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/installation`,
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: "application/vnd.github+json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    },
  );
  if (!installRes.ok) {
    const body = await installRes.text();
    throw new Error(
      `GitHub App installation lookup failed for ${owner}/${repo}: ${installRes.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`,
    );
  }
  const installData = (await installRes.json()) as { id?: number };
  if (typeof installData.id !== "number") {
    throw new Error(
      `GitHub App installation response missing 'id' for ${owner}/${repo}`,
    );
  }

  // Create installation access token
  const tokenRes = await fetch(
    `https://api.github.com/app/installations/${installData.id}/access_tokens`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify({
        repositories: [repo],
        permissions: { contents: "write" },
      }),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    },
  );
  if (!tokenRes.ok) {
    const body = await tokenRes.text();
    throw new Error(
      `GitHub installation token creation failed: ${tokenRes.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`,
    );
  }
  const tokenData = (await tokenRes.json()) as { token?: string };
  if (!tokenData.token) {
    throw new Error(
      `GitHub installation token response missing 'token' for ${owner}/${repo}`,
    );
  }
  return tokenData.token;
}

export interface DispatchPayload {
  service: string;
  /** Env keys that Action A resolved as targets for this Run. */
  environments: string[];
  /**
   * Original `labels` input passed to Action A. Empty when A was invoked
   * with a single `environment` input. Caller workflows can relay this
   * straight to Action B's `labels` input, or use `environments` with a
   * matrix block to fan out per-env.
   */
  labels: string[];
  run_id: string;
  workspace_name: string;
  source_repo: string;
}

/**
 * Fire a `repository_dispatch` event on the target repo.
 */
export async function repositoryDispatch(
  appId: string,
  privateKeyPem: string,
  targetRepo: string,
  eventType: string,
  payload: DispatchPayload,
): Promise<void> {
  const parts = targetRepo.split("/");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error(`Invalid target_repo format: "${targetRepo}" (expected "owner/repo")`);
  }
  const [owner, repo] = parts;
  if (owner.includes("..") || repo.includes("..")) {
    throw new Error(`Invalid target_repo format: "${targetRepo}" (expected "owner/repo", no path traversal)`);
  }

  const token = await getInstallationToken(appId, privateKeyPem, owner, repo);

  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/dispatches`,
    {
      method: "POST",
      headers: {
        Authorization: `token ${token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify({
        event_type: eventType,
        client_payload: payload,
      }),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    },
  );

  if (!res.ok) {
    const body = await res.text();
    throw new Error(
      `repository_dispatch failed for ${targetRepo}: ${res.status} ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`,
    );
  }
}
