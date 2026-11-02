// Versand über Apple Push Notification service (HTTP/2, Token-Authentifizierung mit .p8-Schlüssel).

export interface ApnsConfig {
  /** Inhalt der .p8-Datei (PEM, PKCS#8). */
  key: string;
  keyId: string;
  teamId: string;
  /** Bundle-ID der App, z. B. at.rauscher.carpool. */
  topic: string;
  /** true = Entwicklungs-Server (Debug-Builds aus Xcode), false = TestFlight/App Store. */
  sandbox: boolean;
}

export type SendResult = "sent" | "invalid_token" | "failed";

export interface PushPayload {
  title: string;
  body: string;
  kind: string;
  data: Record<string, string>;
}

const tokenLifetimeMs = 50 * 60 * 1000;
let cached: { jwt: string; createdAt: number } | null = null;

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of raw) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function providerToken(config: ApnsConfig): Promise<string> {
  if (cached && Date.now() - cached.createdAt < tokenLifetimeMs) return cached.jwt;

  const pem = config.key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, [
    "sign",
  ]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: Math.floor(Date.now() / 1000) }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cached = { jwt, createdAt: Date.now() };
  return jwt;
}

export async function sendApns(config: ApnsConfig, deviceToken: string, push: PushPayload): Promise<SendResult> {
  const host = config.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(config)}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({
      aps: { alert: { title: push.title, body: push.body }, sound: "default", "thread-id": push.kind },
      kind: push.kind,
      ...push.data,
    }),
  });
  if (response.ok) return "sent";

  const reason = await response.json().then((b: { reason?: string }) => b.reason).catch(() => undefined);
  if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") return "invalid_token";
  console.error(`APNs ${response.status} ${reason ?? ""}`);
  return "failed";
}
