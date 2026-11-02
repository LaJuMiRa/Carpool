// Texte der Push-Nachrichten (Du-Form, kurz, ohne Ausrufezeichen). Gelten für iOS und Android;
// stehen auch in CLAUDE.md („Push"). Reine Funktionen, getestet in texts.test.ts.

export type ClaimedNotification = {
  id: string;
  kind:
    | "car_free"
    | "booking_displaced"
    | "reservation_soon"
    | "return_overdue"
    | "service_pickerl"
    | "series_occurrence_skipped";
  payload: Record<string, unknown>;
  time_zone: string;
  enabled: boolean;
  car_title: string | null;
  replacement_title: string | null;
  actor_name: string | null;
  tokens: { platform: "ios" | "android"; token: string }[];
};

export type Message = { title: string; body: string };

const fuelLabels: Record<number, string> = { 1: "¼", 2: "½", 3: "¾", 4: "voll" };

function parts(date: Date, timeZone: string) {
  const format = (options: Intl.DateTimeFormatOptions) =>
    new Intl.DateTimeFormat("de-AT", { timeZone, ...options }).format(date).replace(/\./g, "");
  return {
    time: new Intl.DateTimeFormat("de-AT", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .format(date),
    weekday: format({ weekday: "short" }),
    day: format({ day: "numeric" }),
    month: format({ month: "short" }),
    monthLong: format({ month: "long" }),
    year: format({ year: "numeric" }),
    isoDay: new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" })
      .format(date),
  };
}

/** Kalendertage zwischen zwei Daten in der Zeitzone der Familie. */
function dayOffset(date: Date, now: Date, timeZone: string): number {
  const day = (d: Date) => Date.parse(parts(d, timeZone).isoDay + "T00:00:00Z");
  return Math.round((day(date) - day(now)) / 86_400_000);
}

/** „17:30" in der Zeitzone der Familie. */
export function time(date: Date, timeZone: string): string {
  return parts(date, timeZone).time;
}

/** „heute", „morgen", sonst „am Sa, 7. Nov". */
export function onDay(date: Date, now: Date, timeZone: string): string {
  const offset = dayOffset(date, now, timeZone);
  if (offset === 0) return "heute";
  if (offset === 1) return "morgen";
  const p = parts(date, timeZone);
  return `am ${p.weekday}, ${p.day}. ${p.month}`;
}

/** „heute, 10:00–16:00" bzw. „ab 10:00", wenn das Ende fehlt. */
function range(startsAt: Date, endsAt: Date | null, now: Date, timeZone: string): string {
  const from = time(startsAt, timeZone);
  const span = endsAt ? `${from}–${time(endsAt, timeZone)}` : `ab ${from}`;
  return `${onDay(startsAt, now, timeZone)}, ${span}`;
}

function date(value: unknown): Date | null {
  return typeof value === "string" ? new Date(value) : null;
}

/** Text einer Nachricht; null, wenn Angaben fehlen (dann wird sie übersprungen). */
export function buildMessage(n: ClaimedNotification, now: Date): Message | null {
  const car = n.car_title ?? "Das Auto";
  const tz = n.time_zone;
  const p = n.payload;

  switch (n.kind) {
    case "car_free": {
      const fuel = fuelLabels[Number(p.fuel_quarters)];
      const tank = fuel ? `, Tank ${fuel}` : "";
      const who = n.actor_name ? `${n.actor_name} hat ${car} zurückgegeben` : `${car} wurde zurückgegeben`;
      return { title: `${car} ist frei`, body: `${who}${tank}.` };
    }
    case "booking_displaced": {
      const start = date(p.starts_at);
      if (!start) return null;
      const who = n.actor_name ?? "Jemand";
      const lost = `Deine Reservierung ${range(start, date(p.ends_at), now, tz)} fällt weg.`;
      const replacement = n.replacement_title
        ? ` ${n.replacement_title} ist in der Zeit frei.`
        : " Kein anderes Auto ist frei.";
      return { title: `${who} hat ${car} übernommen`, body: lost + replacement };
    }
    case "reservation_soon": {
      const start = date(p.starts_at);
      if (!start) return null;
      return { title: `${car} ab ${time(start, tz)}`, body: "Deine Reservierung beginnt bald." };
    }
    case "return_overdue": {
      const planned = date(p.planned_ends_at);
      if (!planned) return null;
      return { title: `${car} zurückgeben`, body: `Du wolltest ${car} um ${time(planned, tz)} zurückgeben.` };
    }
    case "service_pickerl": {
      const due = typeof p.due_on === "string" ? new Date(`${p.due_on}T12:00:00Z`) : null;
      if (!due) return null;
      const overdue = dayOffset(due, now, tz) < 0;
      if (p.field === "pickerl") {
        const d = parts(due, tz);
        return {
          title: `Pickerl für ${car}`,
          body: overdue ? "Das Pickerl ist abgelaufen." : `Das Pickerl gilt bis Ende ${d.monthLong} ${d.year}.`,
        };
      }
      return {
        title: `Service für ${car}`,
        body: overdue ? "Der Service ist überfällig." : `Der Service ist ${onDay(due, now, tz)} fällig.`,
      };
    }
    case "series_occurrence_skipped": {
      const start = date(p.starts_at);
      if (!start) return null;
      return {
        title: `${car} ${onDay(start, now, tz)} belegt`,
        body: `Dieser Termin deiner Serie wurde nicht angelegt (${range(start, date(p.ends_at), now, tz)}).`,
      };
    }
    default:
      return null;
  }
}
