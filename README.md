# fhem-matrix-bridge

Standalone FHEM module for bidirectional communication between FHEM and a Matrix homeserver.

## Project status
Version: `0.4.0`

## Features

### Outbound (FHEM → Matrix)
- Password login against the Matrix Client API
- Token caching in a local token file
- Sending plain text and notice messages
- Image/file upload to Matrix
- Plot sending for FHEM SVG plot devices via `sendPlot`, with correct rendering of axis labels, titles, and proper image dimensions for mobile clients
- Room alias mapping (`me`, `all`, etc. to Matrix room IDs)
- Usable with plain Matrix rooms or with bridged rooms such as mautrix-whatsapp portal rooms

### Inbound (Matrix → FHEM)
- Receives Matrix messages via `/sync` long-polling (non-blocking)
- Configurable bot keyword (e.g. `!fhem`) — bot only reacts to messages starting with this prefix
- User whitelist (`allowedUsers`) for access control
- `list` — shows all controllable devices with alias and current state
- Device control via FHEM alias (e.g. `!fhem Wohnzimmerlampe on`)
- FHEM room-based scoping (`exposeRoom`) — only exposed devices are controllable
- Optional raw FHEM command passthrough (`cmd`, requires `allowRawCmds 1`)
- Persistent `since` token — no duplicate messages after restart

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

For plot rendering from FHEM SVG devices (recommended):
- `rsvg-convert` from `librsvg2-bin` — renders SVG text, CSS, and axis labels correctly
- `Image::LibRSVG` — used as fallback if `rsvg-convert` is not available (may have issues with complex CSS selectors)

On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install librsvg2-bin           # recommended
sudo apt install libimage-librsvg-perl  # fallback
```

On Arch Linux:

```bash
sudo pacman -S librsvg
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

### Outbound (sending messages)

```text
define MatrixBot MatrixBridge
attr MatrixBot matrixBaseUrl http://127.0.0.1:8008
attr MatrixBot matrixUser matrixbot
attr MatrixBot matrixPassword CHANGE_ME_STRONG_PASSWORD
attr MatrixBot roomMap me=!roomid_me:example.org,all=!roomid_all:example.org
attr MatrixBot autoLogin 1
set MatrixBot login
set MatrixBot send me Test from FHEM
set MatrixBot send all Washing machine done
```

### Inbound (receiving commands)

```text
attr MatrixBot botKeyword !fhem
attr MatrixBot allowedUsers @user:example.org
attr MatrixBot exposeRoom MatrixControl
attr MatrixBot syncEnabled 1
```

Then in the Matrix chat:
```text
!fhem list                        → list devices with state
!fhem Wohnzimmerlampe on          → control a device
!fhem cmd set Dummy 1             → raw FHEM command (requires allowRawCmds 1)
```

Controllable devices are defined via the FHEM room `exposeRoom`:
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
