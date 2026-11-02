# Carpool – Projektanleitung für Claude Code

Native iPhone-App, mit der eine Familie (5 Personen, 3 Autos) sieht und regelt, wer wann welches Auto fährt. Sprache der App und dieser Anleitung: Deutsch (Österreich), Du-Form.

Referenzen (privat, nur für Laurenz sichtbar; bei Bedarf Screenshots ins Repo legen unter `docs/mockups/`):
- Finale Mockups mit Animations-Steckbriefen: https://claude.ai/artifact/WKEXn46j1Np4qeSDHaMmaB (Reihe „Final", F01–F17)
- Design System „Carpool": https://claude.ai/artifact/H39sYS7PHmsEpRg5CNqJ7K

## Tech-Stack

- **iOS 26**, Xcode 26, Swift 6, **SwiftUI** mit Observation (`@Observable`). Kein UIKit außer wo nötig.
- **Liquid Glass** über Systemkomponenten (`TabView`, `.sheet`, Toolbar) und `.buttonStyle(.glass)` / `.glassProminent`.
- **Supabase** (Postgres, Auth, Realtime, Storage, Edge Functions) mit `supabase-swift`.
- Login: **E-Mail + Passwort** über Supabase Auth (Sign in with Apple später, sobald ein Apple-Developer-Konto da ist).
- Erweiterungen: **WidgetKit** (Widgets), **ActivityKit** (Live-Aktivität + Dynamic Island), **App Intents** (Kurzbefehl „Auto zurückgeben", Siri).
- Push über APNs, ausgelöst aus Supabase Edge Functions.
- Verteilung zunächst über **TestFlight** an die Familie.

## Später: Android-App in Kotlin

Geplant ist eine zweite, native Android-App (Kotlin, Jetpack Compose, Material 3) auf **dasselbe Supabase-Backend**. Daraus folgen Regeln für die iOS-App ab dem ersten Tag:
- **Keine Geschäftslogik in der App.** Konflikte prüfen, freie Autos finden, Verdrängen, Rückgängig, Benachrichtigen laufen ausschließlich als RPC/Edge Functions. Die App zeigt nur an und ruft auf.
- **Plattformneutrale Schnittstellen:** RPC-Parameter und Rückgaben als schlichtes JSON, Zeiten immer als UTC-Zeitstempel, keine iOS-Begriffe in Tabellen oder Funktionsnamen.
- **Push neutral halten:** `device_tokens` mit Spalte `platform` (`ios`/`android`); Edge Functions verschicken über APNs bzw. später FCM.
- **Texte und Regeln dokumentieren:** Nutzertexte und Regeln stehen in dieser Datei, nicht nur im Swift-Code, damit die Android-App dieselben übernehmen kann.
- iOS-spezifisch bleiben nur Oberfläche, Widgets, Live-Aktivität und Kurzbefehl.

## Projektstruktur (Vorschlag)

```
Carpool/                 App-Target
  App/                   Einstieg, Splash, Navigation (TabView)
  Features/
    Overview/            Übersicht, Nehmen
    CarDetail/           Auto-Detail, Schäden
    Return/              Rückgabe-Sheet, Tank-Regler
    Calendar/            Kalender, Kontextmenü
    Booking/             Reservieren, Konflikt, Übernehmen
    Members/             Mitglieder, Einladung
    Settings/            Einstellungen, Auto hinzufügen
  Data/                  Supabase-Client, Repositories
CarpoolKit/              Swift Package, geteilt mit Extensions
  Sources/CarpoolKit/    Modelle + Logik (CarStatus, FuelLevel, Backend)
  Sources/CarpoolUI/     Design System: Color Sets, Tokens, Bausteine, Vorschau-Seite
CarpoolWidgets/          Widget-Extension inkl. Live Activity
supabase/
  migrations/            SQL, versioniert
  functions/             Edge Functions (TypeScript)
```

## Funktionen und Regeln

### Belegung
- **Spontan:** „Nehmen" belegt ein freies Auto sofort (offene Fahrt ohne Endzeit). „Zurückgeben" beendet die Fahrt.
- **Reservieren:** im Voraus, einmalig oder **wiederkehrend** (z. B. Mo–Do 07:00–17:00).
- Ein Auto ist **frei**, **reserviert** (Reservierung beginnt bald bzw. liegt im gewählten Zeitraum) oder **unterwegs** (offene Fahrt).

### Konflikte
1. **Wer zuerst bucht, hat das Auto.**
2. Ist ein Auto im gewünschten Zeitraum belegt, zeigt die App **direkt im Formular**, wer es hat, und bietet **alle freien Autos** für genau diesen Zeitraum zum Tauschen an. Kein separates Konflikt-Sheet.
3. **Hauptnutzer-Vorrang:** Jedes Auto hat optional einen Hauptnutzer. Er darf fremde **zukünftige Reservierungen** übernehmen („verdrängen").
   - Eine **laufende Fahrt** kann nie verdrängt werden.
   - Vor dem Übernehmen: Bestätigung (destruktive Aktion), ein Satz Text.
   - Der Verdrängte bekommt eine Push-Nachricht und ein freies Ersatzauto vorgeschlagen. Gibt es keins, sieht der Hauptnutzer vorher eine Warnung und muss bewusst bestätigen.
   - Der Hauptnutzer sieht nicht, welches Ersatzauto vorgeschlagen wird.

### Rückgabe
- Einzige Eingabe: **Tankstand** in Vierteln (¼, ½, ¾, voll) über einen ziehbaren Regler. Vorausgewählt: zuletzt gemeldeter Stand.
- Die nächste Person mit Reservierung wird benachrichtigt.
- Nach Nehmen und Zurückgeben: **keine Rückfrage**, sondern Hinweis mit „Rückgängig" (ca. 5 s).

### Autos
- Anlegen über **Marke + Modell + Farbe**; das freigestellte Fahrzeugbild wird automatisch gesucht (Anbieter noch offen, siehe unten). Optional Spitzname, Kennzeichen, Hauptnutzer.
- Anzeige: Spitzname groß, Modell klein darunter. Ohne Spitzname steht das Modell oben. Detail-Titel: `Golf – „Radieschen"` (Spitzname kursiv).
- Jedes Auto bekommt eine Kalenderfarbe (`car-1` … `car-n`).
- Zustand: Tankstand, Pickerl bis, Service fällig, Kilometer optional.
- **Schäden** melden mit Foto, Text und „fahrbereit ja/nein". Offene Schäden: Warn-Icon auf der Karte, eigener Bereich im Detail.

### Mitglieder
- Familie mit **Einladungscode** (z. B. `K7P-2QX`) bzw. Teilen-Link.
- Rollen: Admin (verwaltet Autos und Hauptnutzer), Mitglied.
- Avatar = erste zwei Buchstaben des Vornamens („Li", „Pa").

### Benachrichtigungen (jeweils abschaltbar)
Auto wieder frei · Meine Buchung wurde übernommen · Reservierung beginnt bald · Rückgabe überfällig · Service und Pickerl.

### Schnellzugriff ohne App öffnen
- **Widgets:** groß (alle Autos + Zurückgeben), klein (eigenes Auto + Zurückgeben), klein (nächste Fahrt).
- **Live-Aktivität** solange man fährt: Auto, Fahrzeit, wer als Nächstes dran ist, Button „Zurückgeben". Dynamic Island zeigt Fahrzeit.
- **Kurzbefehl/Siri:** „Auto zurückgeben" fragt nur nach dem Tankstand.

## Datenmodell (Supabase, Ausgangspunkt)

```sql
families      (id uuid pk, name text, invite_code text unique, created_at)
members       (id uuid pk, family_id fk, user_id fk auth.users, first_name text,
               short text check (char_length(short) = 2), role text check (role in ('admin','member')))
cars          (id uuid pk, family_id fk, make text, model text, paint text, nickname text null,
               plate text null, primary_member_id fk members null, color_slot int,
               image_url text null, fuel_quarters int check (fuel_quarters between 1 and 4),
               pickerl_until date null, service_due date null, odometer_km int null, archived bool default false)
bookings      (id uuid pk, family_id fk, car_id fk, member_id fk,
               starts_at timestamptz, ends_at timestamptz null,        -- null = laufende Fahrt
               kind text check (kind in ('reservation','trip')),
               series_id uuid null,                                      -- wiederkehrende Serie
               status text check (status in ('active','completed','cancelled','displaced')),
               displaced_by fk members null, fuel_quarters_on_return int null, created_at,
               planned_ends_at timestamptz null, fuel_quarters_on_take int null) -- ergänzt in Phase 2
booking_series(id uuid pk, car_id fk, member_id fk, rrule text, start_time time, end_time time, until date null)
damages       (id uuid pk, car_id fk, reported_by fk members, description text,
               photo_path text null, drivable bool, created_at, resolved_at null)
device_tokens (member_id fk, platform text check (platform in ('ios','android')), token text, updated_at)
settings      (member_id pk, notify_* bool …, calendar_car_animation text check in ('once','loop','off'),
               launch_animation text check in ('first','always'))
```

- **Überschneidungen in der Datenbank verhindern:** `btree_gist` + Exclusion-Constraint auf `bookings` (`car_id WITH =`, `tstzrange(starts_at, coalesce(ends_at,'infinity')) WITH &&`) für `status = 'active'`.
- Wiederkehrende Buchungen als Serie speichern und für die nächsten Wochen als einzelne `bookings` materialisieren (Cron), damit Konflikte über dieselbe Constraint laufen.
- **Row Level Security:** Jede Tabelle nur für Mitglieder derselben `family_id`. Autos/Hauptnutzer ändern nur Admins.
- Schreibende Logik als **RPC/Edge Functions**, nicht direkt aus der App: `take_car`, `return_car(fuel)`, `reserve(car, start, end, rrule?)`, `free_cars(start, end)`, `displace(booking_id)` (prüft Hauptnutzer + nicht laufend, setzt Status, schickt Push, schlägt Ersatz vor), `undo_last_action`.
- **Realtime** auf `bookings`, `cars`, `damages` für Live-Status in Übersicht, Kalender und Mitglieder.
- Storage-Bucket `damage-photos`, privat, RLS nach Familie.

## Backend-API (Stand Phase 2)

Migrationen in `supabase/migrations/`, Tests in `supabase/tests/booking_rules.test.sql` und `family_edit.test.sql` (pgTAP, laufen in einer Transaktion mit Rollback; per Supabase-Connector ausführen; Test-E-Mails `@rules.local` / `@edit.local`, damit sie nicht mit den echten Testkonten kollidieren), Beispiel-Familie in `supabase/seed.sql`.

**Lesen** direkt aus den Tabellen (RLS: nur eigene Familie). **Schreiben** über RPCs; direkt erlaubt sind nur: Autos anlegen/ändern (Admin), Familienname (Admin), eigener Vorname, Schaden melden/erledigen, eigene Einstellungen.

| RPC | Zweck | Antwort |
| --- | --- | --- |
| `create_family(p_family_name, p_first_name)` | neue Familie, Aufrufer wird Admin | `{family_id, member_id, invite_code}` |
| `join_family(p_invite_code, p_first_name)` | beitreten; gleichnamiges, noch nicht beigetretenes oder entferntes Mitglied wird übernommen; höchstens 5 falsche Codes in 15 min je Konto | `{ok:true, family_id, member_id, role}` oder `{ok:false, reason:'invalid_invite_code'}` |
| `delete_account()` | eigenes Konto löschen: nicht während einer Fahrt; letzter beigetretener Admin muss erst jemand anderen zum Admin machen; als einziges beigetretenes Mitglied wird die Familie mitgelöscht, sonst wie `remove_member` ausgetragen | `{ok, family_deleted}` |
| `remove_member(p_member_id)` | Mitglied entfernen (Admin; nicht sich selbst, nicht während einer Fahrt) | `{ok, cancelled_count}` |
| `regenerate_invite_code()` | neuer Code (Admin) | Code |
| `take_car(p_car_id)` | Nehmen; eigene Reservierung (läuft oder beginnt in ≤ 15 min) wird zur Fahrt | `{ok, booking_id, from_reservation}` |
| `return_car(p_fuel_quarters, p_car_id?)` | Zurückgeben, Tank 1–4 | `{ok, booking_id}` |
| `undo_last_action()` | Nehmen/Zurückgeben rückgängig, 15 s Fenster | `{ok, kind, booking_id}` |
| `reserve(p_car_id, p_starts_at, p_ends_at, p_rrule?, p_until?, p_displace?, p_accept_no_replacement?)` | Reservieren, optional wöchentlich und mit Verdrängen | `{ok:true, booking_ids, series_id, displaced_count}` oder `{ok:false, reason, conflicts[], free_car_ids[]}` |
| `check_reservation(…, p_booking_id?)` | wie `reserve`, bucht nicht (Hinweis im Formular); mit `p_booking_id` für das Bearbeiten | wie oben |
| `update_booking(p_booking_id, p_car_id, p_starts_at, p_ends_at, p_displace?, p_accept_no_replacement?)` | eigene Reservierung ändern (Auto, Zeit), Übernehmen wie bei `reserve` | wie `reserve` |
| `extend_booking(p_booking_id, p_ends_at)` | eigene Reservierung (neues Ende) oder laufende Fahrt (neues geplantes Ende) verlängern | `{ok:true}` oder `{ok:false, reason:'conflict', conflicts[]}` |
| `transfer_booking(p_booking_id, p_member_id)` | eigene Reservierung an jemand übergeben (bekommt Nachricht) | `{ok}` |
| `free_cars(p_starts_at, p_ends_at, p_booking_id?)` | freie Autos im Zeitraum (bearbeitete Buchung zählt nicht) | Liste `cars` |
| `displace(p_booking_id, p_accept_no_replacement?)` | einzelne Reservierung übernehmen (Hauptnutzer) | `{ok, replacement_found}` oder `{ok:false, reason:'no_replacement'}` |
| `cancel_booking(p_booking_id, p_whole_series?)` | eigene Reservierung stornieren | `{ok, cancelled_count}` |
| `register_device(p_platform, p_token)` / `unregister_device(p_token)` | Push-Token | – |

`conflicts[]`: `{booking_id, kind, starts_at, ends_at, member_id, first_name, can_displace}`. `reason`: `conflict` (normal), `not_displaceable` (Verdrängen nicht erlaubt), `no_replacement` (Warnung vor dem Bestätigen).

**Fehlercodes** (Exception-Text, Code `P0001`) → Nutzertext in der App:
`not_authenticated`, `not_a_member`, `already_member`, `invalid_invite_code`, `too_many_attempts`, `name_taken`, `cannot_remove_self`, `member_driving`, `transfer_admin_first`, `not_editable`, `admin_required`, `last_admin`, `member_not_in_family`, `car_not_found`, `car_busy`, `car_reserved`, `already_driving`, `no_running_trip`, `invalid_fuel`, `invalid_range`, `starts_in_past`, `range_too_long`, `invalid_rrule`, `invalid_until`, `series_must_end_same_day`, `no_occurrences`, `conflict_retry`, `booking_not_found`, `not_owner`, `not_cancellable`, `not_displaceable`, `nothing_to_undo`, `undo_expired`.

**Festgelegte Regeln** (über die Anleitung oben hinaus):
- Eine laufende Fahrt blockiert das Auto bis zu ihrem geplanten Ende, wenn das noch in der Zukunft liegt. Ohne geplantes Ende oder wenn es überfällig ist, blockiert sie bis **eine Stunde ab jetzt** (`private.open_trip_block()`); Reservierungen danach sind erlaubt. Vorher blockierte sie nur bis „jetzt“, man konnte ein unterwegs befindliches Auto „ab jetzt“ reservieren.
- Pro Person höchstens eine laufende Fahrt, pro Auto höchstens eine.
- Nehmen ist gesperrt, wenn gerade die Reservierung von jemand anderem läuft.
- Reservierung max. 14 Tage, Beginn nicht in der Vergangenheit (5 min Toleranz).
- Serien: nur wöchentlich (`FREQ=WEEKLY;BYDAY=MO,TU,…`), Ende am selben Tag, Zeiten in der Zeitzone der Familie (`families.time_zone`, Standard Europe/Vienna). Termine werden 8 Wochen im Voraus angelegt; Cron täglich 02:15 UTC ergänzt. Belegte Termine werden übersprungen, Inhaber bekommt `series_occurrence_skipped`.
- Ersatzauto beim Verdrängen: erstes freies Auto nach Kalenderfarbe.
- Benachrichtigungen landen in `notifications` (Outbox, `send_after`); „Auto wieder frei“ wird 15 s verzögert, damit Rückgängig sie zurückziehen kann. Versand per Edge Function folgt in Phase 7.
- Schadenfotos im Bucket `damage-photos` unter `<family_id>/<datei>`.

## Übersicht und Texte (Stand Phase 4)

Berechnet in `CarpoolKit/Sources/CarpoolKit/Overview/OverviewState.swift` (reine Anzeige-Logik, für Android übernehmen):
- Titel `„{frei} von {alle} frei"`; gezählt werden Autos mit Status frei (ohne das eigene).
- Status je Auto: **unterwegs** bei laufender Fahrt; **reserviert**, wenn eine Reservierung läuft oder in ≤ 60 min beginnt; sonst **frei**. Eigene Reservierung: Statuswort „für dich", Nehmen erlaubt.
- Detailzeile: „Mama, zurück um 17:30" (geplantes Ende) bzw. „Mama, seit 09:12"; „Felix ab 14:00" / „Felix bis 19:00"; „Deine Reservierung ab 14:00"; frei mit Reservierung heute: „Frei bis 14:00, dann Felix" („dann du").
- Eigene Fahrt (Karte oben): „Du fährst seit 09:12", „Tank beim Nehmen ¾", Hinweis „Jonas braucht ihn ab 18:00" (anderer Tag: „ab morgen 08:00", „ab Mo 08:00"), Button „Zurückgeben". Darunter „Andere Autos".
- „Nehmen" nur, wenn man selbst nicht fährt und das Auto frei oder für einen selbst reserviert ist.
- Rückgabe-Sheet: „{Auto} zurückgeben", „Seit 09:12 unterwegs", Tank-Regler (vorausgewählt: zuletzt gemeldeter Stand), „{Name} bekommt eine Nachricht, dass {Auto} bereit ist."
- Rückgängig-Hinweis 5 s: „{Auto} gehört dir" / „{Auto} zurückgegeben", Button „Rückgängig".
- Fehlertexte je Fehlercode: `CarpoolKit/Sources/CarpoolKit/API/CarpoolError.swift` (z. B. `car_busy` → „Das Auto ist gerade unterwegs.").

## Kalender und Reservieren (Stand Phase 5)

Berechnet in `CarpoolKit/Sources/CarpoolKit/Calendar/CalendarState.swift` und `…/Booking/` (`ReservationDraft`, `ReservationTexts`, `ReservationModel`); Zeiten in der Zeitzone der Familie.
- **Kalender:** Titel = Monat des gewählten Tags („Oktober", anderes Jahr „Jänner 2027"), Buttons „Heute" und „+" (Reservieren für den gewählten Tag). Woche Mo–So, je Tag Punkte in den Farben der gebuchten Autos. Wischen blättert eine Woche. Tagestitel „Heute" / „Morgen" / „Gestern" / „Samstag, 31. Oktober"; leer: „Nichts reserviert."
- Buchung erscheint an jedem Tag, den sie berührt. Zeittext: „08:00–17:30", laufende Fahrt ohne Plan „seit 09:12", über Mitternacht „ab 18:00" / „bis 10:00" / „ganztägig". Laufende Fahrt mit Auto-Icon, Serie mit Wiederholen-Icon.
- **Kontextmenü (F11):** eigene Reservierung → „Bearbeiten" (Formular „Reservierung ändern", ohne Schnellwahl und Wiederholen; läuft sie schon, bleibt der Beginn), „Verlängern" (Untermenü „Bis 19:30" / „Bis 20:00" / „Bis 21:00": +30 min, +1 h, +2 h ab dem Ende), „An jemand übergeben" (Untermenü mit allen anderen Mitgliedern, Bestätigung „Reservierung an Felix übergeben?" / „Felix bekommt eine Nachricht. Danach gehört die Reservierung nicht mehr dir."), „Löschen" (Serie: „Nur diesen Termin löschen" / „Diesen und alle folgenden löschen"). Eigene laufende Fahrt → nur „Verlängern" (ab dem geplanten Ende, ohne Plan ab jetzt auf 5 min aufgerundet). Belegt beim Verlängern jemand das Auto: Hinweis wie im Formular („Lisa hat Flitzer von 19:30 bis 21:00."). Fremde zukünftige Reservierung auf einem Auto, dessen Hauptnutzer ich bin → „Übernehmen". Bearbeitete oder übergebene Serientermine lösen sich aus der Serie.
- **Vergangene Tage** zeigen auch abgeschlossene Fahrten und vorbei gegangene Reservierungen (gedämpft, ohne Aktionen), Zeit „09:12–11:40". Geladen je angezeigter Woche (`bookings` mit Status active/completed, Ende ≤ jetzt).
- **Formular:** Schnellwahl „Jetzt" (auf 5 min aufgerundet, 2 h), „Heute Abend" (18:00–22:00, nur vor 18:00), „Morgen" (08:00–17:00), „…" (eigener Zeitraum). Startwert: heute „Jetzt", morgen „Morgen", sonst der Tag 08:00–17:00. Vorausgewähltes Auto: eines, dessen Hauptnutzer ich bin, sonst das erste nach Kalenderfarbe.
- Zeile „Sa, 31. Okt · 10:00 – 16:00"; „Wiederholen": „Nie", „Jeden Sa", „Mo–Do", „Mo, Mi, Fr", „Jeden Tag", mit Ende „Mo–Do bis 30. Nov"; nur wenn die Reservierung am selben Tag endet (sonst „nur am selben Tag").
- Jede Änderung wird geprüft (`check_reservation` + `free_cars`, 250 ms entprellt). Kacheln: „frei" / „belegt".
- **Konflikt-Hinweis:** „Felix hat Octavia von 10:00 bis 16:00." (anderer Tag: „… morgen von …", „… am Samstag von …"), „Mama fährt Octavia bis 17:30.", „Mama ist gerade mit Octavia unterwegs.", „Du hast Octavia schon von …", mehrere Termine „Felix hat Octavia an 3 Terminen." / „Octavia ist an 3 Terminen belegt.". Darunter alle freien Autos zum Tauschen, als Hauptnutzer „Übernehmen"; ohne beides „Kein anderes Auto ist frei.". Primär-Button dann gesperrt: „Octavia ist belegt".
- **Übernehmen (F14):** „Felix’ Buchung übernehmen?" (Genitiv: Name auf s/ß/x/z → ’, sonst „Lisas"), „Felix verliert die Reservierung morgen, 10:00–16:00, und bekommt eine Nachricht.", Button „Octavia übernehmen" (danger), „Abbrechen". Ohne Ersatzauto danach: „Kein Ersatzauto frei" / „Für Felix ist in dieser Zeit kein anderes Auto frei. Willst du trotzdem übernehmen?" / „Trotzdem übernehmen".

## Mitglieder, Einstellungen, Autos, Schäden (Stand Phase 6)

Berechnet in `CarpoolKit/Sources/CarpoolKit/Members/MembersState.swift`, `…/CarDetail/CarDetailState.swift`, `…/Cars/CarForm.swift`. Schreiben direkt auf die Tabellen (RLS erlaubt es): eigener Name/Kürzel, Rollen und Familienname (Admin), Autos (Admin), Schäden, Einstellungen.
- **Mitglieder (F15):** Titel = Familienname, Zahnrad → Einstellungen. Zeile: Avatar (blass = noch nicht beigetreten), Name („Lisa (du)"), Admin-Badge. Zweite Zeile in dieser Reihenfolge: „fährt gerade Octavia" (Statusfarbe unterwegs) → „Hauptnutzer von Flitzer" (+ „· heute 18:00" bei nächster Fahrt, Punkt in Autofarbe) → „nächste Fahrt heute 14:00" / „morgen 08:00" / „Mo 08:00" → „noch nicht beigetreten". Admins: Kontextmenü „Zum Admin machen" / „Admin-Rechte entfernen" und „Aus der Familie entfernen" (Bestätigung „Felix entfernen?" / „Felix sieht die Familie danach nicht mehr. Künftige Reservierungen werden gelöscht."). Entfernte bleiben als Zeile mit `removed_at` erhalten (Namen in alten Fahrten), erscheinen aber in keiner Liste; ihre künftigen Reservierungen, Serien, Hauptnutzer-Rollen und Geräte werden entfernt. Treten sie mit demselben Vornamen wieder bei, bekommen sie ihr altes Mitglied zurück.
- Einladung: Code in SF Mono, „Einladung teilen" (Teilen-Blatt): „Komm in unsere Familie „{Name}“ bei Carpool. Melde dich in der App an und gib diesen Code ein: {Code}".
- **Einstellungen (F16):** Profil (Vorname, Kürzel; Kürzel folgt dem Namen, bis man es selbst ändert), Familie (nur Admin: Name, „Neuer Einladungscode" mit Bestätigung „Der alte Code funktioniert dann nicht mehr."), Autos (Admin: bearbeiten, „Auto hinzufügen"), 5 Benachrichtigungs-Schalter, Darstellung: Erscheinungsbild System/Hell/Dunkel (nur auf dem Gerät), Startanimation Erster Start/Immer, Fahrendes Auto Einmal/Dauerhaft/Aus (Kalender), Abmelden und „Konto löschen“ (rot, eine Karte). Konto löschen fragt nach: „Konto löschen?“ / „Deine Anmeldung wird gelöscht. Deine vergangenen Fahrten bleiben für die Familie sichtbar. Das lässt sich nicht rückgängig machen.“ (als einziges Mitglied mit Konto: „Du bist das einzige Mitglied mit Konto. „Familie Berger“ wird mit allen Autos und Buchungen gelöscht. …“), Buttons „Konto löschen“ / „Abbrechen“.
- **Auto hinzufügen (F17):** ein Feld „Marke und Modell"; erstes Wort = Marke (bekannte Mehrwort-Marken wie „Land Rover" erkannt), Rest = Modell; bei nur einem Wort Hinweis „Marke und Modell, z. B. „VW Golf“". Lackfarben schwarz, weiß, silber, blau, rot, grau, grün; Bild erscheint mit Überblenden + Unschärfe 300 ms. Optional Spitzname, Hauptnutzer, Kennzeichen (groß geschrieben). Bearbeiten zusätzlich Pickerl bis, Service fällig, Kilometerstand und „Auto entfernen" (archiviert).
- **Auto-Detail (F05):** Tippen auf Auto in der Übersicht (Zoom-Übergang). Status „bei dir · seit 09:12" bzw. wie Übersicht, „Hauptnutzer: Papa" / „du". Buttons: Zurückgeben (eigene Fahrt) oder Nehmen + Reservieren (mit diesem Auto). Schäden mit „Melden"; „Keine offenen Schäden."; Zeile „Kratzer …" + „Lisa, 12. Okt · fahrbereit" / „nicht fahrbereit". Nächste Buchungen (max. 4): „Heute, 18:00–22:00" / „Morgen, …" / „Mo, 2. Nov, …", Person bzw. „Papa, jede Woche". Zustand: Tank, Pickerl „bis März 2027" (≤ 30 Tage gelb, danach „abgelaufen" rot; gilt bis Monatsende), Service „heute" / „morgen" / „in 5 Tagen" / „in 3 Wochen" / „Mai 2027" (≤ 30 Tage gelb, „überfällig" rot), Kennzeichen, Kilometerstand.
- **Schaden melden:** Foto (Kamera oder Mediathek, verkleinert auf max. 1600 px, JPEG 0,7) nach `damage-photos/<family_id>/<uuid>.jpg`, „Was ist passiert?" (Pflicht, max. 1000 Zeichen), „Fahrbereit" (Standard ja). Offene Schäden: Warn-Icon an der Karte. Schaden antippen → Foto groß, „Erledigt" (mit Bestätigung) setzt `resolved_at`, leert `photo_path` und löscht das Foto aus dem Bucket (jedes Familienmitglied darf Fotos der Familie löschen; schlägt das Löschen fehl, bleibt nur die Datei liegen).

## Push, Widgets, Live-Aktivität, Kurzbefehl (Stand Phase 7)

**Push** (Migration `…_push.sql`, Edge Function `supabase/functions/send-push`):
- Alle Nachrichten laufen über die Outbox `notifications`. Cron jede Minute: `private.queue_reminders()` legt „Reservierung beginnt bald" (≤ 15 min vorher) und „Rückgabe überfällig" (geplantes Ende + 15 min) an; täglich 06:00 UTC `private.queue_car_reminders()` für Pickerl/Service (einmal je Auto und Termin, sobald ≤ 30 Tage; an den Hauptnutzer, sonst an alle Admins). Jede Minute ruft `private.dispatch_push()` die Edge Function auf, wenn etwas fällig ist.
- `send-push` holt mit `claim_push_batch()` (nur `service_role`) bis zu 100 fällige Nachrichten, markiert sie als verschickt, beachtet die Schalter in `settings` und schickt an alle Geräte (iOS über APNs; Android/FCM folgt). Ungültige Token löscht `drop_device_tokens()`.
- App: fragt nach dem Anmelden nach der Erlaubnis, meldet das Token mit `register_device('ios', …)` an und beim Abmelden ab. Antippen öffnet: Rückgabe überfällig → Rückgabe-Sheet; übernommen, übergeben, beginnt bald, Serie → Kalender; Pickerl/Service → Auto-Detail; sonst Übersicht. Im Vordergrund als Banner.
- **Texte** (`texts.ts`, für iOS und Android gleich): „Radieschen ist frei" / „Lisa hat Radieschen zurückgegeben, Tank ¾." · „Papa hat Radieschen übernommen" / „Deine Reservierung morgen, 10:00–16:00 fällt weg. Flitzer ist in der Zeit frei." (sonst „Kein anderes Auto ist frei.") · „Radieschen ab 14:00" / „Deine Reservierung beginnt bald." · „Radieschen zurückgeben" / „Du wolltest Radieschen um 17:30 zurückgeben." · „Pickerl für Radieschen" / „Das Pickerl gilt bis Ende November 2026." („Das Pickerl ist abgelaufen.") · „Service für Radieschen" / „Der Service ist morgen fällig." („Der Service ist überfällig.") · „Radieschen am Mo, 2. Nov belegt" / „Dieser Termin deiner Serie wurde nicht angelegt (am Mo, 2. Nov, 08:00–17:00)." · „Lisa hat dir Radieschen gegeben" / „Die Reservierung morgen, 10:00–16:00 gehört jetzt dir." Übersprungene Serientermine und übergebene Reservierungen hängen am Schalter „Meine Buchung wurde übernommen".
- Einrichten (einmalig, sobald das Apple-Developer-Konto da ist): APNs-Schlüssel (.p8) anlegen; `supabase secrets set APNS_KEY=… APNS_KEY_ID=… APNS_TEAM_ID=… APNS_TOPIC=at.rauscher.carpool APNS_SANDBOX=true PUSH_DISPATCH_SECRET=…`; im Vault `project_url` und `push_dispatch_secret` (gleicher Wert) anlegen; Function deployen (`npx supabase functions deploy send-push`). Ohne Schlüssel antwortet die Function mit 503 und lässt die Nachrichten liegen. Nachrichten, die beim Abholen mehr als 1 h überfällig sind (z. B. aus der Zeit vor dem Einrichten), werden nur als erledigt markiert, nicht verschickt.
- Texte testen: `node --test supabase/functions/send-push/texts.test.ts`.

**Widgets** (F09; Logik `CarpoolKit/…/QuickAccess/WidgetState.swift`, Ansichten `CarpoolUI/QuickAccess/`):
- Die App speichert nach jeder Änderung den Snapshot im App-Group-Ordner (`SharedSnapshotStore`) und lädt die Widgets neu; beim Abmelden wird er gelöscht. Widgets brauchen kein Netzwerk und keine Anmeldung; die Zeitleiste rechnet den Stand für jede Buchungsgrenze der nächsten 12 h neu.
- „Alle Autos" (mittel: 3 Autos, groß: bis 6): „Carpool", „1 von 3 frei", je Auto Bild, Name, Status („bei dir" für das eigene), darunter „Radieschen zurückgeben".
- „Mein Auto" (klein): gefahrenes Auto mit „bei dir" und „Zurückgeben"; sonst das Auto, dessen Hauptnutzer ich bin, mit Detailzeile; sonst „Du fährst gerade nicht.".
- „Nächste Fahrt" (klein): während der Fahrt die nächste Person auf meinem Auto („18:00", „Jonas nimmt Radieschen"), sonst meine nächste Reservierung („Du nimmst Flitzer"); anderer Tag darüber („Morgen" / „Mo, 2. Nov"); leer „Nichts geplant.".
- Ohne gespeicherten Stand: „Öffne die App, um dich anzumelden.".

**Live-Aktivität** (F08): startet, sobald ich eine laufende Fahrt habe (auch per Realtime oder Kurzbefehl), endet bei der Rückgabe. Sperrbildschirm: Auto, „Du fährst seit 09:12", Fahrzeit (System-Timer), Fortschritt von Beginn bis zur nächsten Reservierung, „09:12" · „Jonas ab 18:00", Button „Zurückgeben". Dynamic Island: Auto-Symbol in Autofarbe + Fahrzeit; aufgeklappt mit Zurückgeben.

**Deep Links** (`carpool://`): `overview`, `return` (Rückgabe-Sheet der eigenen Fahrt), `calendar`, `car/<id>`.

**Kurzbefehl/Siri** „Auto zurückgeben" (`ReturnCarIntent`): läuft ohne App zu öffnen; fragt „Wie voll ist der Tank von Radieschen?" (¼ ½ ¾ voll), antwortet „Radieschen zurückgegeben." bzw. „Du fährst gerade kein Auto.", „Melde dich zuerst in der App an.". Siri-Sätze: „Auto zurückgeben mit Carpool", „Carpool Auto zurückgeben", „Mit Carpool zurückgeben".
- Einstellungen → Schnellzugriff: „Widgets" (Anleitung + Vorschau mit echten Daten inkl. Live-Aktivität), „Kurzbefehle und Siri" (Siri-Satz, Link in die Kurzbefehle-App).

## Splash, Icon, TestFlight (Stand Phase 8)

- **Splash (F01)** in `CarpoolKit/Sources/CarpoolUI/Splash/` (`KeyBoardScene`, `SplashView`, Ablauf `SplashTimeline` als `KeyframeTimeline`): mittlerer Schlüssel fällt in 0,5 s auf den Haken (leichte Haptik), pendelt aus (10° → −7° → 4° → −2° → 0, zuletzt bounce 0.3), stößt erst den linken, dann den rechten Schlüssel an; ab 1,35 s steigt „Carpool“ 8 pt auf. Endstand 0,45 s, dann 200 ms ausblenden; gesamt gut 2 s. Tippen überspringt. „Bewegung reduzieren“ und VoiceOver: alles steht, nur der Titel blendet 150 ms ein.
- Der Splash liegt über der App, die darunter schon lädt. Ob er erscheint, entscheidet `LaunchSplashStore` auf dem Gerät („Erster Start“: nur einmal je Gerät; „Immer“: jeder Start), weil die Einstellungen beim Start noch nicht geladen sind; die App spiegelt `settings.launch_animation` dorthin, sobald sie geladen oder geändert wird.
- Debug: in `-previewFamily`, `-designCatalog` und mit `DEV_EMAIL` kein Splash; `-splash` erzwingt ihn, `-splashHold` lässt den Endstand 8 s stehen (`SplashUITests`).
- **App-Icon:** Schlüsselbrett aus derselben Szene (`AppIconArtwork`), Hell und Dunkel ohne Alphakanal, Tinted in Graustufen mit transparentem Grund. Neu erzeugen: `cd CarpoolKit && TEST_RUNNER_EXPORT_APP_ICON=$PWD/../Carpool/Resources/Assets.xcassets/AppIcon.appiconset xcodebuild test -scheme CarpoolKit-Package -destination '…' -only-testing:CarpoolUITests`.
- Statuswechsel überblenden mit 2 pt Unschärfe (`AnyTransition.statusFade`).
- **Für TestFlight vorbereitet:** Privacy-Manifeste (`PrivacyInfo.xcprivacy` in App und Widgets: UserDefaults CA92.1; erhobene Daten E-Mail, Name, Fotos, Inhalte – nur für die App-Funktion, kein Tracking), `ITSAppUsesNonExemptEncryption = NO`, Release-Build kompiliert (Vorschauen mit `PreviewAPI` nur im Debug).
- **TestFlight hochladen** (sobald das Developer-Konto da ist): `DEVELOPMENT_TEAM` in `project.yml` setzen, `xcodegen generate`; in App Store Connect App mit Bundle-ID `at.rauscher.carpool` anlegen; App ID mit App Group und Push, Widget-ID `.widgets` mit App Group; `CURRENT_PROJECT_VERSION` bei jedem Upload erhöhen; Xcode → Product → Archive → Distribute → TestFlight. Beim Export setzt Xcode `aps-environment` auf `production`; in Supabase dazu `APNS_SANDBOX=false`. Familie als interne Tester (bis 100, ohne Review) oder externe Gruppe (kurzes Review).

## Entwicklung und Tests
- Testkonten (nur Entwicklung, Passwort beim Projektinhaber): `papa@test.local` (Papa, Admin), `lisa@test.local` (Lisa), `neu@test.local` (ohne Familie). Vor dem echten Einsatz löschen.
- Automatische Anmeldung im Debug-Build: Umgebungsvariablen `DEV_EMAIL`/`DEV_PASSWORD`, im Simulator per `SIMCTL_CHILD_DEV_EMAIL=… SIMCTL_CHILD_DEV_PASSWORD=… xcrun simctl launch …`.
- UI-Test Kernablauf gegen das echte Backend (`CarpoolAppUITests`): `TEST_RUNNER_DEV_EMAIL=lisa@test.local TEST_RUNNER_DEV_PASSWORD=… xcodebuild test …`; ohne die Variablen wird er übersprungen.
- **Beispiel-Familie ohne Netzwerk** (nur Debug): Startargument `-previewFamily` öffnet die App als Lisa mit `PreviewAPI` (Lisa ist Hauptnutzerin von Flitzer; Konflikte grob nachgestellt). Lisa ist dort Admin, Mama Hauptnutzerin von Radieschen (mit Schaden). Darauf laufen `CalendarFlowUITests` (Konflikt → Tauschen → Übernehmen), `FamilyFlowUITests` (Auto-Detail, Schaden melden, Mitglieder, Einstellungen, Auto hinzufügen) und `QuickAccessFlowUITests` (Widget-Vorschau, Kurzbefehl-Seite, Deep Links) ohne Testkonto.
- Supabase Auth: „Confirm email" für die Testphase ausschalten (Dashboard → Authentication → Sign In / Providers → Email), sonst braucht jede Registrierung einen Bestätigungslink.

## Design System

Grundsätze: ruhig statt laut, viel Weißraum, **Linien statt Schatten** für Inhalte, Farbe nur für Autos und Status, Farbe nie ohne Wort/Namen. Titel nur, wenn sie etwas aussagen („1 von 3 frei", Familienname) – nie „Kalender" o. Ä. und kein Datum oben.

### Farben (Light / Dark) – als Color Sets im Asset-Katalog, Namen 1:1
| Token | Light | Dark | Einsatz |
| --- | --- | --- | --- |
| paper | #fafaf7 | #0e0e0d | Seitenhintergrund |
| surface | #ffffff | #181817 | Karten, Felder |
| ink | #111111 | #f2f1ec | Text, Primär-Button |
| ink-secondary | #4a4a46 | #b5b4ae | Sekundärtext |
| ink-muted | #6b6b66 | #8e8d88 | Labels, Metadaten |
| on-ink | #fafaf7 | #111111 | Text auf ink |
| hairline | #e4e3de | #2a2a28 | Trennlinien, Kartenrand |
| hairline-strong | #bdbcb5 | #4a4a46 | Ränder von Bedienelementen |
| status-free | #1e7b4f | #5cc48e | frei |
| status-reserved | #8c6a12 | #e0b44c | reserviert |
| status-busy | #b4531a | #f0965a | unterwegs |
| danger | #b3261e | #f2847a | Schäden, verdrängen |
| car-1 / -tint / -ink | #3e8a63 / #dde9e1 / #1f4d36 | #6fbf93 / #1e3328 / #a9d8bc | Auto 1 |
| car-2 / -tint / -ink | #c08a1e / #f1e5cc / #5c4310 | #e2b660 / #3a2f17 / #ebcb85 | Auto 2 |
| car-3 / -tint / -ink | #3f6ea6 / #d9e3ee / #1e3f63 | #7fa8d8 / #1c2b3d / #a9c6e8 | Auto 3 |

### Typografie
Nur **SF Pro** über Systemstile mit Dynamic Type: `.largeTitle` (bold, enger gesetzt) für Screen-Titel, `.title`/`.title2` (bold) für Sheet-Titel und Spitznamen, `.headline` für Buttons und Namen, `.body`, `.callout`, `.caption` (medium) für Labels. Keine Serifenschrift. Einladungscode in SF Mono.

### Abstände und Formen
Abstände 4 / 8 / 12 / 16 / 24 / 40 pt. Seitenrand 24, Kartenpadding 16. Radien: 6 (Buchungsblöcke, Segmente), 14 (Karten, Buttons), Kapsel (Avatare, Chips). Buttons 50 pt hoch; höchstens **ein Primär-Button** pro Screen.

### Liquid Glass
Nur auf der Navigationsebene: schwebende Tab-Bar (Autos · Kalender · Mitglieder), runde Glas-Buttons (Zurück, Schließen, Einstellungen, Plus), kleine Sheets schwebend. Inhalte bleiben flach. Zwischen Inhalt und schwebender Leiste weicher Scroll-Kanten-Effekt, keine harte Linie.

## Bewegung

Grundsatz: nur mit Zweck (Feedback, räumlicher Zusammenhang, Zustandswechsel). Häufige Aktionen ohne Zier: **Tab-Wechsel, Scrollen, Woche blättern, Tag antippen, Chips → sofort.** Standard-Feder `.spring(duration: 0.3, bounce: 0)`; Nachfedern (`bounce: 0.2–0.3`) nur nach Gesten mit Schwung. Nie ease-in. Alles unterbrechbar.

| Stelle | Bewegung |
| --- | --- |
| Splash (F01) | Brett + äußere Schlüssel stehen; mittlerer Schlüssel fliegt einmal von oben auf den freien Haken, pendelt gedämpft aus (bounce 0.3), stößt Nachbarn kurz an; dann „Carpool" 8 pt aufsteigend, 250 ms. **Nur beim ersten Start**, Tippen überspringt. |
| Buttons | beim Drücken sofort auf 0.97, 120 ms |
| Nehmen (F04) | Zeile rückt an die Stelle „Du fährst" (Feder 0.3 s), andere weichen 40 ms versetzt aus; Fahrt-Infos blenden in 200 ms ein; Status überblendet mit 2 pt Unschärfe; Haptik Erfolg |
| Rückgängig-Hinweis | 250 ms von unten herein, nach 5 s auf demselben Weg 200 ms hinaus; Timer pausiert im Hintergrund |
| Auto-Detail (F05) | Fahrzeugbild als gemeinsames Element von der Karte ins Detail (`matchedGeometryEffect`/Zoom-Übergang), Feder 0.35 s, zurück auf demselben Weg |
| Tank-Regler (F06) | folgt dem Daumen 1:1, beim Greifen 1.08; beim Loslassen Feder (bounce 0.2) auf nächste Viertelstufe, Haptik pro Stufe; Zahl überblendet 150 ms |
| Kalender (F10) | Auto-Icon bei laufender Fahrt fährt beim Öffnen **einmal** ein (500 ms ease-out), dann steht es; Einstellung: einmal / dauerhaft / aus. Neue Buchung von anderen: 8 pt einschweben + einblenden 250 ms |
| Kontextmenü (F11) | System-Kontextmenü; Block hebt sich, Menü wächst aus dem Block |
| Konflikt (F12) | Hinweis klappt in 200 ms auf; Tauschen: Auswahlrahmen springt per Feder |
| Live-Status | „fährt gerade", Statuswechsel: Überblenden 200 ms |
| Auto hinzufügen | Fahrzeugbild erscheint mit Überblenden + Unschärfe 300 ms |

**Barrierefreiheit:** „Bewegung reduzieren" → Bewegungen werden zu kurzem Überblenden, kein Pendeln/Einfahren. „Transparenz reduzieren" → Glas wird feste Fläche. VoiceOver-Labels für Autos (Spitzname + Modell + Status), Status nie nur über Farbe. Dynamic Type bis mindestens XXL testen.

## Texte
Du-Form, kurz, keine Ausrufezeichen. Buttons mit Verb: „Nehmen", „Zurückgeben", „Reservieren", „Rückgängig". Status als ein Wort: frei, reserviert, unterwegs. Personen mit Vornamen, Autos mit Spitznamen.

## Vorgehen (Phasen)

1. **Setup:** Xcode-Projekt mit Targets (App, Widgets), Swift Package `CarpoolKit`, Supabase-Projekt, `supabase/` mit lokaler Entwicklung (Supabase CLI).
2. **Backend:** Migrationen (Schema, Constraint, RLS), RPCs/Edge Functions, Seed-Daten für die Beispiel-Familie (Papa, Mama, Lisa, Jonas, Felix; Golf „Radieschen", Škoda Octavia, Toyota Yaris „Flitzer"). Tests für Konfliktregeln und Verdrängen.
3. **Design System in SwiftUI:** Color Sets, Abstände, Bausteine; eine Vorschau-Seite mit allen Bausteinen.
4. **Kernablauf:** Login (E-Mail + Passwort) + Familie beitreten → Übersicht → Nehmen → Rückgabe → Rückgängig. Realtime.
5. **Kalender + Reservieren** inkl. Wiederholung, Konflikt im Formular, Übernehmen.
6. **Mitglieder, Einstellungen, Auto hinzufügen, Schäden.**
7. **Push**, dann **Widgets, Live-Aktivität, App Intents.**
8. **Splash + Feinschliff der Animationen** am echten iPhone, dann TestFlight.

Arbeitsweise: nach jeder Phase bauen und im Simulator prüfen; keine Phase überspringen; Entscheidungen, die von dieser Anleitung abweichen, kurz hier dokumentieren.

## Entscheidungen und Abweichungen

- **Xcode 27** statt 26 installiert; Deployment-Target bleibt **iOS 26.0**. Simulator: iOS 26.5.
- Xcode-Projekt wird mit **XcodeGen** aus `project.yml` erzeugt (`xcodegen generate`); `Carpool.xcodeproj` ist nicht eingecheckt.
- **Supabase CLI über npm** (`npx supabase …`, Version in `package.json`), weil Homebrew veraltete Command Line Tools meldet.
- Bundle-ID `at.rauscher.carpool` (Widgets `.widgets`), App Group `group.at.rauscher.carpool`. Team für Geräte-Builds noch nicht gesetzt.
- **Backend direkt in der Supabase-Cloud** (Projekt „Carpool", Ref `ybceqcsvlhbbzjlczvaq`, eu-west-1), bearbeitet über den Supabase-Connector; kein lokaler Docker-Stack. Migrationen trotzdem als SQL-Dateien in `supabase/migrations/` ablegen.
- Supabase-URL/Key (Publishable Key) über `Config/Secrets.xcconfig` (nicht eingecheckt, Vorlage `Secrets.example.xcconfig`) → Info.plist → `SupabaseConfig`.
- **Design System liegt im Package als `CarpoolUI`** (nicht in `Carpool/DesignSystem/`), damit Widgets und Live-Aktivität dieselben Farben und Bausteine nutzen. Color Sets in `CarpoolKit/Sources/CarpoolUI/Resources/Colors.xcassets`, Namen 1:1 wie in der Token-Tabelle.
- Bausteine: `PrimaryButtonStyle`/`SecondaryButtonStyle`/`CompactButtonStyle`/`DestructiveButtonStyle`, `Avatar`, `StatusLabel`, `CarDot`, `CarTitle`/`CarDetailTitle` (`CarNaming`), `CarSilhouette`, `CarRow`, `CarTile`, `CarSelectRow`, `BookingBlock`, `InfoBanner`, `Chip`, `FuelPicker`, `FuelGauge`, `cardStyle()`, `SectionHeader`, `PropertyRow`, `Hairline`. Tokens: `Spacing`, `Radius`, `ControlSize`, `Motion`, Schriftstile (`screenTitleStyle()` …).
- Kalenderfarben: drei Farbsätze; ab dem 4. Auto wiederholen sie sich (`CarColor(slot:)`).
- Fahrzeugbild vorerst `CarSilhouette`: Form (Limousine/Kompakt/Kombi) wird aus dem Modellnamen geschätzt, Farbe aus dem Lack-Freitext (`PaintColor`). Dunkle Lacke bekommen eine feine Kontur.
- Vorschau-Seite: App mit Startargument `-designCatalog` starten (nur Debug), optional `-designCatalogSection "Autos"` springt zu einem Abschnitt.
- Kalender-Titel zeigt den Monat (wie Mockup F10), obwohl die Grundsätze „kein Datum oben" sagen – ohne Monat ist die Woche nicht einzuordnen.
- Übernehmen-Text sagt „die Reservierung" statt „seine Reservierung" (Mockup F14), damit er für alle Namen passt.
- Auto-Icon im Kalender: „Einmal" = beim ersten Erscheinen je Fahrt, „Dauerhaft" = alle 6 s einfahren/ausblenden, „Aus" = steht.
- Auto-Detail (F05) kam in Phase 6 dazu, weil die Schäden dort leben.
- Beitreten mit falschem Code liefert `{ok:false}` statt einer Exception: eine Exception würde den gezählten Fehlversuch zurückrollen.
- Mitglieder entfernen ist ein Soft-Delete (`members.removed_at`), weil Buchungen per `on delete cascade` an Mitgliedern hängen; echtes Löschen würde die Fahrten-Historie mitnehmen.
- Bearbeiten nutzt dieselbe Prüfung wie Reservieren (`reserve_impl` mit `p_booking_id`); beim Übernehmen gilt das alte Auto der bearbeiteten Buchung schon als frei für das Ersatzauto.
- Konto löschen ist eine RPC (`delete_account`, löscht auch `auth.users`), keine Edge Function; danach meldet die App nur lokal ab. Schadenfotos einer mitgelöschten Familie bleiben im Bucket liegen (Storage lässt sich nicht per SQL leeren).
- Buttons über eine ganze Zeile: Rahmen und `contentShape` gehören ins Label, nicht um den Button – sonst ist nur der Text tippbar („Abmelden“ war davon betroffen).
- Beispiel-Familie (`-previewFamily`) schreibt nichts aufs Gerät (keine Widgets, keine Live-Aktivität, kein Push): sonst bleiben Beispieldaten in Widgets, und das Ende der Live-Aktivität startet die App ohne Startargumente neu (machte UI-Tests wackelig).
- Erscheinungsbild wird nur auf dem Gerät gespeichert (`@AppStorage`), nicht in `settings`. Startanimation steht in `settings` und wird für den Splash zusätzlich auf dem Gerät gespiegelt.
- „Zurückgeben" in Widget und Live-Aktivität öffnet das Rückgabe-Sheet in der App (Deep Link), statt direkt zurückzugeben: der Tankstand ist Pflicht und lässt sich im Widget nicht abfragen. Direkt ohne App geht es über den Kurzbefehl.
- Live-Aktivität wird lokal von der App gesteuert (kein Push-Update). Nach Änderungen durch andere aktualisiert sie sich, sobald die App läuft; der Timer läuft vom System weiter.
- Push-Versand: Nachrichten werden beim Abholen als verschickt markiert; schlägt APNs vorübergehend fehl, gehen sie verloren (für eine Familie vertretbar, kein Retry). „Auto wieder frei" kommt damit nach 15 s bis gut 1 min.
- Siri-Hinweis als eigene Zeile statt `SiriTipView` (zeigt im Simulator nur einen Platzhalter).
- Splash-Einstellung wird zusätzlich auf dem Gerät gespiegelt (`LaunchSplashStore`), weil der Splash vor Anmeldung und Laden der Einstellungen läuft. Auf einem neuen Gerät gilt daher beim allerersten Start immer „Erster Start“.
- App-Icon wird aus SwiftUI gerendert statt gezeichnet: Splash und Icon bleiben dieselbe Form. Das Brett läuft im Icon bis an den Rand, damit die Schlüssel klein lesbar bleiben.
- Splash-Titel mit fester Größe (44 pt), nicht Dynamic Type: er ist Teil der Marke, kein Lesetext.
- DerivedData nicht im Projektordner ablegen (iCloud-Ordner hängt Metadaten an → Codesign-Fehler „detritus not allowed").

## Offene Punkte
- **Push scharf schalten:** Apple-Developer-Konto, APNs-Schlüssel, Secrets und Vault-Einträge (siehe „Push"); Migration `…_push.sql` ist eingespielt (Cron-Jobs laufen, sammeln aber nur in der Outbox); Function `send-push` ist noch nicht deployt. `aps-environment` steht auf `development` (Xcode setzt beim TestFlight-Export `production`); dann `APNS_SANDBOX=false`.
- Push für Android (FCM) in `send-push` ergänzen.
- **Anbieter für Fahrzeugbilder** (freigestellt, nach Marke/Modell/Farbe): Kosten, Lizenz und Abdeckung prüfen; bis dahin neutrale Silhouette je Karosserieform.
- **App-Store-Name:** „Carpool" ist vermutlich vergeben; Anzeigename auf dem iPhone bleibt „Carpool", Store-Eintrag ggf. „Carpool – Familienautos". Für TestFlight egal.
- **Feinschliff am echten iPhone** (Phase 8) steht noch aus: Splash-Timing und Haptik, Nehmen/Zurückgeben, Tank-Regler, Zoom-Übergang und Dynamic Type XXL am Gerät prüfen. Geht erst mit Developer-Konto (oder kostenlosem Team für eigenes Gerät).
- Supabase-Sicherheitshinweise: „Leaked Password Protection" im Dashboard einschalten (Authentication → Passwords); `pg_net` liegt im Schema `public` (kam mit der Push-Migration); `public.rls_auto_enable()` ist eine Supabase-eigene Funktion, die `anon` aufrufen darf – prüfen, ob sie gebraucht wird. Die Hinweise zu `SECURITY DEFINER`-RPCs sind gewollt (so ist die API gebaut).
- Beispiel-Familie Berger liegt in der Cloud-Datenbank; vor dem echten Einsatz löschen (`delete from families where invite_code = 'K7P-2QX'`).
