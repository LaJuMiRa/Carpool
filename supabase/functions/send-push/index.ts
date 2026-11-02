// Edge Function "send-push": holt fällige Nachrichten aus der Outbox (claim_push_batch) und
// verschickt sie an die Geräte der Empfänger. Wird jede Minute von pg_cron (private.dispatch_push)
// mit dem Geheimnis PUSH_DISPATCH_SECRET aufgerufen.
//
// Secrets (supabase secrets set …): PUSH_DISPATCH_SECRET, APNS_KEY (Inhalt der .p8),
// APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC (Bundle-ID), APNS_SANDBOX ("true" für Debug-Builds).

import { createClient } from "npm:@supabase/supabase-js@2";
import { type ApnsConfig, sendApns } from "./apns.ts";
import { buildMessage, type ClaimedNotification } from "./texts.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function apnsConfig(): ApnsConfig | null {
  const key = Deno.env.get("APNS_KEY");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const topic = Deno.env.get("APNS_TOPIC");
  if (!key || !keyId || !teamId || !topic) return null;
  return { key, keyId, teamId, topic, sandbox: Deno.env.get("APNS_SANDBOX") === "true" };
}

function stringData(payload: Record<string, unknown>): Record<string, string> {
  return Object.fromEntries(
    ["car_id", "booking_id"].filter((k) => typeof payload[k] === "string").map((k) => [k, payload[k] as string]),
  );
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("PUSH_DISPATCH_SECRET");
  if (!secret || request.headers.get("Authorization") !== `Bearer ${secret}`) {
    return json({ error: "unauthorized" }, 401);
  }
  // Ohne APNs-Schlüssel nichts abholen, damit die Nachrichten in der Outbox bleiben.
  const apns = apnsConfig();
  if (!apns) return json({ error: "apns_not_configured" }, 503);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await supabase.rpc("claim_push_batch", { p_limit: 100 });
  if (error) {
    console.error("claim_push_batch", error.message);
    return json({ error: "claim_failed" }, 500);
  }

  const now = new Date();
  const counts = { sent: 0, skipped: 0, failed: 0 };
  const invalidTokens: string[] = [];

  for (const notification of (data ?? []) as ClaimedNotification[]) {
    const message = buildMessage(notification, now);
    const devices = notification.tokens.filter((t) => t.platform === "ios"); // Android (FCM) folgt.
    if (!notification.enabled || !message || devices.length === 0) {
      counts.skipped++;
      continue;
    }
    const push = { ...message, kind: notification.kind, data: stringData(notification.payload) };
    const results = await Promise.all(devices.map((d) => sendApns(apns, d.token, push)));
    results.forEach((result, i) => {
      if (result === "invalid_token") invalidTokens.push(devices[i].token);
    });
    if (results.includes("sent")) counts.sent++;
    else counts.failed++;
  }

  if (invalidTokens.length > 0) {
    const { error: dropError } = await supabase.rpc("drop_device_tokens", { p_tokens: invalidTokens });
    if (dropError) console.error("drop_device_tokens", dropError.message);
  }
  return json(counts);
});
