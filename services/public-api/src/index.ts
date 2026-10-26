import { createApp, type ContentBundle } from "./app";
import bundle from "./generated/bundle.json";

export interface Env {
  NWS_USER_AGENT?: string;
}

let app: ReturnType<typeof createApp> | undefined;

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    app ??= createApp({
      bundle: bundle as unknown as ContentBundle,
      nws: {
        fetch: (input, init) => fetch(input, init),
        userAgent: env.NWS_USER_AGENT ?? "DryRun-public-api/0.1 (contact: set NWS_USER_AGENT)",
        timeoutMs: 8000,
        now: () => new Date(),
      },
    });
    return app.fetch(request, env, ctx);
  },
};
