# Optional Discord relay

This Worker forwards validated numeric candidates to Discord; it stores no timing database and never publishes profiles to GitHub. It has **not been deployed**.

1. In a Cloudflare account, choose an unused numeric rate-limit namespace ID in `wrangler.jsonc` if the supplied ID is already used.
2. Deploy this folder with Wrangler. Add `DISCORD_WEBHOOK` using the Cloudflare secret facility (`wrangler secret put DISCORD_WEBHOOK`), not a repository file or ordinary public variable.
3. Set `PUBLIC_REPORT_URL` in the distributed Lua script to `https://YOUR-WORKER.workers.dev/report` and publish that update.
4. Test one candidate with reporting explicitly enabled. HTTP 204 means Discord accepted it; 429 returns a retry interval. The script retries failed delivery.

Only place 8248288152 and the documented candidate schema are accepted. The body is bounded to 4 KiB, batches to six profiles, and markers to .03–8 seconds. Outbound text is reconstructed to strip arbitrary text/identity fields and disable mentions. No client can supply a destination webhook. No response contains the private URL or upstream error body.

The shared rate binding allows approximately 15 requests per minute **per Cloudflare location**. It is not a strict worldwide Discord quota or authentication. A hostile client can forge a candidate or exhaust the shared allowance; reports therefore require human review and must never directly edit the public script. Additional per-client authentication or stronger abuse controls can be added for larger deployments.

The relay does not intentionally log IPs or player identities; the hosting provider still handles normal request metadata. Public submission is opt-in in the Lua interface. No hosting account, deployment or paid resource was created for this release.

References: [Worker secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [rate-limit semantics](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [Discord webhook execution](https://docs.discord.com/developers/resources/webhook#execute-webhook).
