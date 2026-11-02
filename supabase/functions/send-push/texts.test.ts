// Ausführen: node --test supabase/functions/send-push/texts.test.ts  (Node ≥ 23, ohne Abhängigkeiten)
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildMessage, type ClaimedNotification, onDay } from "./texts.ts";

const tz = "Europe/Vienna";
// Freitag, 30.10.2026, 12:00 in Wien (UTC+1)
const now = new Date("2026-10-30T11:00:00Z");

function notification(kind: ClaimedNotification["kind"], payload: Record<string, unknown>,
                      extra: Partial<ClaimedNotification> = {}): ClaimedNotification {
  return {
    id: "n1", kind, payload, time_zone: tz, enabled: true, car_title: "Radieschen", replacement_title: null,
    actor_name: null, tokens: [], ...extra,
  };
}

test("Auto wieder frei", () => {
  assert.deepEqual(buildMessage(notification("car_free", { fuel_quarters: 3 }, { actor_name: "Lisa" }), now), {
    title: "Radieschen ist frei",
    body: "Lisa hat Radieschen zurückgegeben, Tank ¾.",
  });
});

test("Buchung übernommen, mit und ohne Ersatzauto", () => {
  const payload = { starts_at: "2026-10-31T09:00:00Z", ends_at: "2026-10-31T15:00:00Z" };
  assert.deepEqual(
    buildMessage(notification("booking_displaced", payload, { actor_name: "Papa", replacement_title: "Flitzer" }), now),
    {
      title: "Papa hat Radieschen übernommen",
      body: "Deine Reservierung morgen, 10:00–16:00 fällt weg. Flitzer ist in der Zeit frei.",
    },
  );
  assert.equal(
    buildMessage(notification("booking_displaced", payload, { actor_name: "Papa" }), now)?.body,
    "Deine Reservierung morgen, 10:00–16:00 fällt weg. Kein anderes Auto ist frei.",
  );
});

test("Reservierung übergeben", () => {
  const payload = { starts_at: "2026-10-31T09:00:00Z", ends_at: "2026-10-31T15:00:00Z" };
  assert.deepEqual(buildMessage(notification("booking_transferred", payload, { actor_name: "Lisa" }), now), {
    title: "Lisa hat dir Radieschen gegeben",
    body: "Die Reservierung morgen, 10:00–16:00 gehört jetzt dir.",
  });
});

test("Reservierung beginnt bald und Rückgabe überfällig", () => {
  assert.deepEqual(buildMessage(notification("reservation_soon", { starts_at: "2026-10-30T13:00:00Z" }), now), {
    title: "Radieschen ab 14:00",
    body: "Deine Reservierung beginnt bald.",
  });
  assert.deepEqual(buildMessage(notification("return_overdue", { planned_ends_at: "2026-10-30T10:30:00Z" }), now), {
    title: "Radieschen zurückgeben",
    body: "Du wolltest Radieschen um 11:30 zurückgeben.",
  });
});

test("Pickerl und Service", () => {
  assert.deepEqual(
    buildMessage(notification("service_pickerl", { field: "pickerl", due_on: "2026-11-30" }), now),
    { title: "Pickerl für Radieschen", body: "Das Pickerl gilt bis Ende November 2026." },
  );
  assert.deepEqual(
    buildMessage(notification("service_pickerl", { field: "service", due_on: "2026-10-31" }), now),
    { title: "Service für Radieschen", body: "Der Service ist morgen fällig." },
  );
  assert.equal(
    buildMessage(notification("service_pickerl", { field: "service", due_on: "2026-10-20" }), now)?.body,
    "Der Service ist überfällig.",
  );
});

test("Serientermin übersprungen", () => {
  const payload = { starts_at: "2026-11-02T07:00:00Z", ends_at: "2026-11-02T16:00:00Z" };
  assert.deepEqual(buildMessage(notification("series_occurrence_skipped", payload), now), {
    title: "Radieschen am Mo, 2. Nov belegt",
    body: "Dieser Termin deiner Serie wurde nicht angelegt (am Mo, 2. Nov, 08:00–17:00).",
  });
});

test("Tag relativ zu heute, Mitternacht in Wien", () => {
  // Wien ist ab 25.10. UTC+1: 22:30 UTC = 23:30 (heute), 23:00 UTC = 00:00 (morgen)
  assert.equal(onDay(new Date("2026-10-30T22:30:00Z"), now, tz), "heute");
  assert.equal(onDay(new Date("2026-10-30T23:00:00Z"), new Date("2026-10-30T22:00:00Z"), tz), "morgen");
  assert.equal(onDay(new Date("2026-10-30T20:00:00Z"), now, tz), "heute");
});

test("Fehlende Angaben → keine Nachricht", () => {
  assert.equal(buildMessage(notification("reservation_soon", {}), now), null);
});
