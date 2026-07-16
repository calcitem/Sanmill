// SPDX-License-Identifier: AGPL-3.0-or-later

import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: { bindings: { ONLINE_ENABLED: "true" } },
    }),
  ],
});
