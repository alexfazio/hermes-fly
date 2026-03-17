export type PostDeployCleanupResult =
  | { ok: true }
  | { ok: false; notFound?: boolean; error?: string };

export interface PostDeployCleanupPort {
  destroyDeployment(
    appName: string,
    io: {
      stdout: { write: (s: string) => void };
      stderr: { write: (s: string) => void };
    }
  ): Promise<PostDeployCleanupResult>;
}
