# fhem-matrix-bridge

Standalone FHEM module for bidirectional communication between FHEM and a Matrix homeserver.

## Project status
Version: `0.3.0`

## Features

### Outbound (FHEM → Matrix)
- Password login against the Matrix Client API
- Token caching in a local token file
- Sending plain text and notice messages
- Image/file upload to Matrix
- Plot sending for FHEM SVG plot devices via `sendPlot`
- Room alias mapping (`me`, `all`, etc. to Matrix room IDs)
- Usable with plain Matrix rooms or with bridged rooms such as mautrix-whatsapp portal rooms

### Inbound (Matrix → FHEM)
- Empfang von Matrix-Nachrichten via `/sync` Long-Polling (non-blocking)
- Konfigurierbares Bot-Keyword (z.B. `!fhem`) — Bot reagiert nur auf Nachrichten mit diesem Prefix
- User-Whitelist (`allowedUsers`) für Zugriffskontrolle
- `list` — zeigt alle steuerbaren Geräte mit Alias und aktuellem Status
- Gerätesteuerung über FHEM-Alias (z.B. `!fhem Wohnzimmerlampe on`)
- FHEM-Raum-basiertes Scoping (`exposeRoom`) — nur freigegebene Geräte sind steuerbar
- Optionales Durchreichen roher FHEM-Befehle (`cmd`, erfordert `allowRawCmds 1`)
- Persistenter `since`-Token — keine doppelten Nachrichten nach Neustart

## Folder layout

```text
fhem-matrix-bridge/
├── CHANGELOG.md
├── README.md
├── VERSION
├── FHEM/
│   └── 98_MatrixBridge.pm
├── docs/
│   └── USAGE.md
└── examples/
    └── fhem.cfg.example
```

## Requirements

### FHEM / Perl side
Required Perl/FHEM pieces:
- `HttpUtils`
- `JSON`
- `Encode`
- `Time::HiRes`
- `MIME::Base64`

For plot rendering from FHEM SVG devices:
- `Image::LibRSVG`

On Debian/Ubuntu this usually means:

```bash
sudo apt update
sudo apt install libimage-librsvg-perl
```

### Matrix side
You need:
- a reachable Matrix homeserver
- a dedicated Matrix user for FHEM/bot traffic
- one or more target rooms

Example generic setup:
- homeserver URL: `http://127.0.0.1:8008`
- Matrix user: `matrixbot`
- Matrix user password: your own chosen password

## Installation

Copy the module into your FHEM module directory, for example:

```bash
cp FHEM/98_MatrixBridge.pm /opt/fhem/FHEM/
```

Then in FHEM:

```text
reload 98_MatrixBridge.pm
```

## Minimal generic example

### Outbound (Nachrichten senden)

```text
define MatrixBot MatrixBridge
attr MatrixBot matrixBaseUrl http://127.0.0.1:8008
attr MatrixBot matrixUser matrixbot
attr MatrixBot matrixPassword CHANGE_ME_STRONG_PASSWORD
attr MatrixBot roomMap me=!roomid_me:example.org,all=!roomid_all:example.org
attr MatrixBot autoLogin 1
set MatrixBot login
set MatrixBot send me Test von FHEM
set MatrixBot send all Waschmaschine fertig
```

### Inbound (Befehle empfangen)

```text
attr MatrixBot botKeyword !fhem
attr MatrixBot allowedUsers @user:example.org
attr MatrixBot exposeRoom MatrixControl
attr MatrixBot syncEnabled 1
```

Dann im Matrix-Chat:
```text
!fhem list                        → Geräteliste mit Status
!fhem Wohnzimmerlampe on          → Gerät schalten
!fhem cmd set Dummy 1             → Roher FHEM-Befehl (nur mit allowRawCmds 1)
```

Die steuerbaren Geräte werden über den FHEM-Raum `exposeRoom` definiert:
```text
attr Wohnzimmerlampe room MatrixControl
attr Wohnzimmerlampe alias Wohnzimmerlampe
```

## WhatsApp bridge / relay notes
This module only talks to Matrix.
If a message should leave Matrix and end up on WhatsApp through `mautrix-whatsapp`, the target room must already be:
- a WhatsApp portal room created by the bridge
- joined by the Matrix bot user
- configured for relay in that specific portal room

### Relay permission process (generic)
1. Log in to `mautrix-whatsapp` with the main WhatsApp account.
2. In the bridge config, allow relay mode.
3. In each portal room where the bot should be allowed to speak, run the bridge command to enable relay for the desired login.
4. Invite the Matrix bot user into that portal room.
5. Let the bot user join the room.
6. Only then can the bot user send through that WhatsApp identity in that room.

Important:
- relay is usually room-scoped, not global
- the Matrix bot does **not** automatically get permission to speak in all WhatsApp chats
- using relay means the bot speaks through the selected WhatsApp account, so permissions should stay narrow and intentional

## Permission model recommendation
Recommended setup:
- one non-admin Matrix bot user for FHEM
- no public Matrix registration
- relay only in the rooms that really need it
- a strong password for the bot user
- keep the Matrix server as the central message bus and only use bridges at the edge

## Known good usage pattern
The most robust pattern is:
1. FHEM sends a normal text event
2. optionally FHEM sends a plot/image right after it

This avoids mixing logic into one giant messenger-specific command and works well with Matrix rooms and bridged rooms.

## Next sensible steps
- add Signal bridge integration notes / tested room model
- inventory and remove remaining legacy `Signalbot` leftovers from the live FHEM config
- add automatic room discovery
- improve token/session handling beyond simple cache
