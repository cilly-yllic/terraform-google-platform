import { createAppAuth } from "@octokit/auth-app";
import { Octokit } from "@octokit/rest";

interface GitHubAppOptions {
  appId: string;
  privateKey: string;
}

export async function fetchFileViaApp(
  opts: GitHubAppOptions,
  owner: string,
  repo: string,
  path: string,
  ref?: string
): Promise<string> {
  const appOctokit = new Octokit({
    authStrategy: createAppAuth,
    auth: {
      appId: opts.appId,
      privateKey: opts.privateKey,
    },
  });

  const { data: installation } = await appOctokit.apps.getRepoInstallation({
    owner,
    repo,
  });

  const installationOctokit = new Octokit({
    authStrategy: createAppAuth,
    auth: {
      appId: opts.appId,
      privateKey: opts.privateKey,
      installationId: installation.id,
    },
  });

  const response = await installationOctokit.repos.getContent({
    owner,
    repo,
    path,
    ref,
    mediaType: { format: "raw" },
  });

  if (typeof response.data === "string") {
    return response.data;
  }

  if (
    !Array.isArray(response.data) &&
    "content" in response.data &&
    response.data.content
  ) {
    return Buffer.from(response.data.content, "base64").toString("utf-8");
  }

  throw new Error(`Unexpected response type when fetching ${path} from ${owner}/${repo}`);
}
