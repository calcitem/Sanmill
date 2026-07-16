// SPDX-License-Identifier: AGPL-3.0-or-later

import type { Env } from "./types";

export function inviteLanding(roomId: string, env: Env): Response {
  const nonceBytes = new Uint8Array(16);
  crypto.getRandomValues(nonceBytes);
  const nonce = Array.from(nonceBytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  const sourceBase = env.SOURCE_URL.replace(/\/+$/u, "");
  const sourceUrl = escapeHtml(sourceBase);
  const licenseUrl = escapeHtml(`${sourceBase}/blob/master/Copying.txt`);
  const installUrl = escapeHtml(env.INSTALL_URL);
  const sourceVersion = escapeHtml(env.SOURCE_VERSION);
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Sanmill friend game / Sanmill 好友对战</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #101418; }
    main { width: min(32rem, calc(100% - 2rem)); box-sizing: border-box; padding: 2rem; border-radius: 1rem; background: #1d252c; color: #fff; }
    h1 { margin-top: 0; font-size: 1.5rem; }
    p { line-height: 1.55; color: #d7e0e7; }
    a.button { display: block; margin: 1.5rem 0; padding: .9rem 1rem; border-radius: .6rem; text-align: center; color: #07130d; background: #78d99b; font-weight: 700; text-decoration: none; }
    a.source { color: #9fc9ff; }
  </style>
</head>
<body>
  <main>
    <h1>Sanmill friend game / Sanmill 好友对战</h1>
    <p>Open this invitation in Sanmill to join. No web game is provided.</p>
    <p>请使用 Sanmill 打开此邀请并加入对局。本页面不提供网页对弈。</p>
    <a class="button" id="open" href="sanmill://invite/${roomId}">Open Sanmill / 打开 Sanmill</a>
    <a class="source" href="${installUrl}" rel="noreferrer">Install Sanmill / 安装 Sanmill</a><br>
    <a class="source" href="${sourceUrl}" rel="noreferrer">Source code / 源代码</a><br>
    <a class="source" href="${licenseUrl}" rel="noreferrer">AGPL license / AGPL 许可证</a>
    <p>Deployment / 部署版本: <code>${sourceVersion}</code></p>
  </main>
  <script nonce="${nonce}">
    const target = document.getElementById("open");
    target.href = "sanmill://invite/${roomId}" + location.hash;
  </script>
</body>
</html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "content-security-policy": `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; base-uri 'none'; frame-ancestors 'none'`,
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}

export function appleAssociation(): Response {
  return associationResponse({
    applinks: {
      apps: [],
      details: [
        {
          appID: "A7CJ43TU48.com.calcitem.sanmill",
          components: [{ "/": "/invite/*", comment: "Sanmill friend invitations" }],
        },
      ],
    },
  });
}

export function androidAssociation(env: Env): Response {
  const fingerprints = (env.ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => /^[A-Fa-f0-9]{2}(?::[A-Fa-f0-9]{2}){31}$/u.test(value));
  return associationResponse(
    fingerprints.length === 0
      ? []
      : [
          {
            relation: ["delegate_permission/common.handle_all_urls"],
            target: {
              namespace: "android_app",
              package_name: "com.calcitem.sanmill",
              sha256_cert_fingerprints: fingerprints,
            },
          },
        ],
  );
}

function associationResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
