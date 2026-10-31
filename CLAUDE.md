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

Migrationen in `supabase/migrations/`, Tests in `supabase/tests/booking_rules.test.sql` (pgTAP, läuft in einer Transaktion mit Rollback; per Supabase-Connector ausführen), Beispiel-Familie in `supabase/seed.sql`.

**Lesen** direkt aus den Tabellen (RLS: nur eigene Familie). **Schreiben** über RPCs; direkt erlaubt sind nur: Autos anlegen/ändern (Admin), Familienname (Admin), eigener Vorname, Schaden melden/erledigen, eigene Einstellungen.

| RPC | Zweck | Antwort |
| --- | --- | --- |
| `create_family(p_family_name, p_first_name)` | neue Familie, Aufrufer wird Admin | `{family_id, member_id, invite_code}` |
| `join_family(p_invite_code, p_first_name)` | beitreten; gleichnamiges, noch nicht beigetretenes Mitglied wird übernommen | `{family_id, member_id, role}` |
| `regenerate_invite_code()` | neuer Code (Admin) | Code |
| `take_car(p_car_id)` | Nehmen; eigene Reservierung (läuft oder beginnt in ≤ 15 min) wird zur Fahrt | `{ok, booking_id, from_reservation}` |
| `return_car(p_fuel_quarters, p_car_id?)` | Zurückgeben, Tank 1–4 | `{ok, booking_id}` |
| `undo_last_action()` | Nehmen/Zurückgeben rückgängig, 15 s Fenster | `{ok, kind, booking_id}` |
| `reserve(p_car_id, p_starts_at, p_ends_at, p_rrule?, p_until?, p_displace?, p_accept_no_replacement?)` | Reservieren, optional wöchentlich und mit Verdrängen | `{ok:true, booking_ids, series_id, displaced_count}` oder `{ok:false, reason, conflicts[], free_car_ids[]}` |
| `check_reservation(…)` | wie `reserve`, bucht nicht (Hinweis im Formular) | wie oben |
| `free_cars(p_starts_at, p_ends_at)` | freie Autos im Zeitraum | Liste `cars` |
| `displace(p_booking_id, p_accept_no_replacement?)` | einzelne Reservierung übernehmen (Hauptnutzer) | `{ok, replacement_found}` oder `{ok:false, reason:'no_replacement'}` |
| `cancel_booking(p_booking_id, p_whole_series?)` | eigene Reservierung stornieren | `{ok, cancelled_count}` |
| `register_device(p_platform, p_token)` / `unregister_device(p_token)` | Push-Token | – |

`conflicts[]`: `{booking_id, kind, starts_at, ends_at, member_id, first_name, can_displace}`. `reason`: `conflict` (normal), `not_displaceable` (Verdrängen nicht erlaubt), `no_replacement` (Warnung vor dem Bestätigen).

**Fehlercodes** (Exception-Text, Code `P0001`) → Nutzertext in der App:
`not_authenticated`, `not_a_member`, `already_member`, `invalid_invite_code`, `name_taken`, `admin_required`, `last_admin`, `member_not_in_family`, `car_not_found`, `car_busy`, `car_reserved`, `already_driving`, `no_running_trip`, `invalid_fuel`, `invalid_range`, `starts_in_past`, `range_too_long`, `invalid_rrule`, `invalid_until`, `series_must_end_same_day`, `no_occurrences`, `conflict_retry`, `booking_not_found`, `not_owner`, `not_cancellable`, `not_displaceable`, `nothing_to_undo`, `undo_expired`.

**Festgelegte Regeln** (über die Anleitung oben hinaus):
- Eine laufende Fahrt ohne geplantes Ende blockiert das Auto nur bis „jetzt“; Reservierungen danach sind erlaubt (die Person wird benachrichtigt). Mit geplantem Ende (aus Reservierung) blockiert sie bis dahin.
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

## Entwicklung und Tests
- Testkonten (nur Entwicklung, Passwort beim Projektinhaber): `papa@test.local` (Papa, Admin), `lisa@test.local` (Lisa), `neu@test.local` (ohne Familie). Vor dem echten Einsatz löschen.
- Automatische Anmeldung im Debug-Build: Umgebungsvariablen `DEV_EMAIL`/`DEV_PASSWORD`, im Simulator per `SIMCTL_CHILD_DEV_EMAIL=… SIMCTL_CHILD_DEV_PASSWORD=… xcrun simctl launch …`.
- UI-Test Kernablauf gegen das echte Backend (`CarpoolAppUITests`): `TEST_RUNNER_DEV_EMAIL=lisa@test.local TEST_RUNNER_DEV_PASSWORD=… xcodebuild test …`; ohne die Variablen wird er übersprungen.
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
- DerivedData nicht im Projektordner ablegen (iCloud-Ordner hängt Metadaten an → Codesign-Fehler „detritus not allowed").

## Offene Punkte
- **Anbieter für Fahrzeugbilder** (freigestellt, nach Marke/Modell/Farbe): Kosten, Lizenz und Abdeckung prüfen; bis dahin neutrale Silhouette je Karosserieform.
- **App-Store-Name:** „Carpool" ist vermutlich vergeben; Anzeigename auf dem iPhone bleibt „Carpool", Store-Eintrag ggf. „Carpool – Familienautos". Für TestFlight egal.
- App-Icon: Schlüsselbrett-Motiv aus dem Splash.
- Rate-Limit für `join_family` (Code-Raten) vor TestFlight prüfen.
- Beispiel-Familie Berger liegt in der Cloud-Datenbank; vor dem echten Einsatz löschen (`delete from families where invite_code = 'K7P-2QX'`).
