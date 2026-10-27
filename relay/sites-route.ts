import { env } from "cloudflare:workers";
import relay from "../lib/relay.mjs";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const bindings = env as unknown as { DB: D1Database; DISCORD_WEBHOOK?: string };
  return relay.fetch(request, {
    DISCORD_WEBHOOK: bindings.DISCORD_WEBHOOK,
    REPORT_LIMITER: {
      async limit() {
        const window = Math.floor(Date.now() / 60000);
        const row = await bindings.DB.prepare(`
          INSERT INTO report_quota (key, window, count) VALUES ('global', ?, 1)
          ON CONFLICT(key) DO UPDATE SET
            count = CASE WHEN report_quota.window = excluded.window THEN report_quota.count + 1 ELSE 1 END,
            window = excluded.window
          RETURNING count
        `).bind(window).first<{ count: number }>();
        return { success: !!row && row.count <= 15 };
      },
    },
  });
}

export function GET() {
  return Response.json({ service: "Clover timing relay", method: "POST", schema: 1 });
}
