# Usage

## 1. Define the device in FHEM

```text
define MatrixBot MatrixBridge
```

## 2. Set required attributes

Generic example:

```text
attr MatrixBot matrixBaseUrl http://127.0.0.1:8008
attr MatrixBot matrixUser matrixbot
attr MatrixBot matrixPassword CHANGE_ME_STRONG_PASSWORD
attr MatrixBot roomMap me=!roomid_me:example.org,all=!roomid_all:example.org
attr MatrixBot autoLogin 1
```

### Attribute reference

- `matrixBaseUrl` — Matrix homeserver base URL, e.g. `http://127.0.0.1:8008`
- `matrixUser` — Matrix username without `@` and domain, e.g. `matrixbot`
- `matrixPassword` — password for the Matrix user
- `roomMap` — comma-separated mapping list, e.g. `me=!roomid1:example.org,all=!roomid2:example.org`
- `defaultTarget` — optional fallback target key
- `tokenFile` — optional path for cached token storage
- `autoLogin` — `1` or `0`, whether login should be attempted automatically
- `disableTLSCheck` — optional, useful for test environments only
- `verbose` — reserved for future debugging options

## 3. Login

```text
set MatrixBot login
```

## 4. Send a text message

```text
set MatrixBot send me Test von FHEM
set MatrixBot send all Waschmaschine fertig
```

## 5. Send as notice

```text
set MatrixBot sendNotice me Dies ist eine Statusmeldung
```

## 6. Send an image file

```text
set MatrixBot sendImage me /tmp/test.png
```

## 7. Send a plot from an SVG device

```text
set MatrixBot sendPlot me SVG_PowerPlot
```

Requirements for `sendPlot`:
- the target device must be an FHEM `SVG` device
- `Image::LibRSVG` must be installed on the host

On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install libimage-librsvg-perl
```

## WhatsApp relay usage (generic)
If the target room is a `mautrix-whatsapp` portal room, the following must already be true:
- the bot user has been invited into the portal room
- the bot user has joined the portal room
- relay has been enabled in that exact room for the chosen WhatsApp login

Without those steps, Matrix delivery may succeed while WhatsApp delivery still fails.

## 8. Inbound: Nachrichten empfangen und Geräte steuern

### Konfiguration

```text
attr MatrixBot botKeyword @fhem
attr MatrixBot allowedUsers @user:homeserver.de,@admin:homeserver.de
attr MatrixBot exposeRoom MatrixControl
attr MatrixBot syncEnabled 1
```

### Attribute für Inbound

- `botKeyword` — Prefix, auf das der Bot reagiert (z.B. `@fhem` oder `!fhem`). Ohne dieses Attribut reagiert der Bot auf jede Nachricht.
- `allowedUsers` — Komma-getrennte Liste erlaubter Matrix-User-IDs (z.B. `@user:example.org`). Ohne dieses Attribut darf jeder User im Raum den Bot steuern.
- `exposeRoom` — FHEM-Raum, der die steuerbaren Geräte enthält (z.B. `MatrixControl`). Nur Geräte, die in FHEM diesem Raum zugeordnet sind, können über Matrix gesteuert werden.
- `allowRawCmds` — `0` oder `1`. Erlaubt das Durchreichen roher FHEM-Befehle via `cmd`-Prefix. Standard: `0` (deaktiviert).
- `syncEnabled` — `0` oder `1`. Aktiviert den `/sync` Long-Polling-Listener. Standard: `0`.
- `syncInterval` — Wartezeit in Sekunden bei Sync-Fehler bevor erneut versucht wird. Standard: `5`.

### Befehle im Matrix-Chat

```text
@fhem list                        → Zeigt alle steuerbaren Geräte mit Status
@fhem Wohnzimmerlampe on          → Schaltet Gerät über Alias oder FHEM-Name
@fhem Kaffeemaschine off          → Weitere Geräte steuern
@fhem cmd set Dummy 1             → Roher FHEM-Befehl (nur mit allowRawCmds 1)
```

### Manuelles Starten/Stoppen

```text
set MatrixBot startSync
set MatrixBot stopSync
```

### FHEM-Raum vorbereiten

Damit der Bot Geräte steuern kann, müssen diese in FHEM dem `exposeRoom` zugeordnet sein:

```text
attr Wohnzimmerlampe room MatrixControl
attr Wohnzimmerlampe alias Wohnzimmerlampe
attr Kaffeemaschine room MatrixControl
attr Kaffeemaschine alias Kaffeemaschine
```

Der Bot nutzt das `alias`-Attribut als Anzeigename. Ist kein Alias gesetzt, wird der FHEM-Gerätename verwendet.

## Readings

The module updates readings such as:
- `state`
- `lastError`
- `lastEventId`
- `lastTarget`
- `lastRoom`
- `lastResult`
- `user_id`
- `device_id`
- `syncState` — Status des Sync-Listeners (`running`, `stopped`, `error`)
- `lastInboundSender` — Matrix-ID des letzten Absenders
- `lastInboundRoom` — Raum-ID der letzten eingehenden Nachricht
- `lastInboundMessage` — Inhalt der letzten eingehenden Nachricht (nach Keyword-Stripping)

## FHEM notify example

```text
define n_WaschmaschineFertig notify Waschmaschine:done set MatrixBot send all Waschmaschine fertig
```

## Recommended room naming strategy
Use generic semantic room aliases instead of personal identifiers, for example:
- `me`
- `all`
- `alarm`
- `status`

This keeps the FHEM config portable and avoids baking person-specific naming into the module usage.

## Current limitations

- no automatic room discovery yet
- token reuse is simple cache-based reuse, not a full session manager
- bridge permission handling is intentionally manual and explicit
- inbound commands work only for `m.text` messages (no reactions, edits, etc.)
