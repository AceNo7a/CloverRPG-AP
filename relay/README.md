# Discord relay

Production endpoint: https://clover-timing-relay.indigoamber16384.chatgpt.site/report

The deployed Sites application accepts anonymous v5/v6 numeric candidates and forwards validated batches to Discord. DISCORD_WEBHOOK is stored as a server-side runtime secret. The deployed application has an atomic D1-backed anonymous counter (one row) allowing 15 requests/minute globally. It stores no timing database or player profiles. Discord delivery failures return sanitized errors or retry intervals.

worker.mjs contains the shared validation and forwarding code. sites-route.ts shows the deployed route adapter; schema.sql is its counter schema. The original wrangler.jsonc is an alternative standalone Cloudflare deployment configuration, using approximate per-location limits instead of the deployed global D1 counter. Never commit a real webhook token.

The body limit is 4 KiB and the batch limit is six profiles. Place, client version, marker ranges, sample counts and spread are validated. Outgoing text is reconstructed; identity fields/arbitrary messages cannot pass through. Mentions are disabled. The client cannot choose the webhook destination, and responses never expose its URL or upstream error body.

This is a public, unauthenticated candidate inbox. Clients can forge data or exhaust its shared allowance. Human review is required; reports never directly alter the public script. The hosting provider still processes ordinary HTTP metadata. Reporting is automatic and disclosed in the client GUI/README; unloading stops further client submissions.

References: [Sites deployment](https://clover-timing-relay.indigoamber16384.chatgpt.site), [Discord webhook execution](https://docs.discord.com/developers/resources/webhook#execute-webhook).
