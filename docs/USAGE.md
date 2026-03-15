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

- outbound sending only
- no inbound Matrix command processing yet
- no automatic room discovery yet
- token reuse is simple cache-based reuse, not a full session manager
- bridge permission handling is intentionally manual and explicit
