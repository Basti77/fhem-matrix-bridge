# fhem-matrix-bridge

Standalone FHEM module project for sending messages from FHEM to a Matrix homeserver.

The project is meant to stay independent from the live FHEM config so it can be:
- versioned cleanly
- documented properly
- tested separately
- published to GitHub later

## Project status
Version: `0.2.0`

Current scope:
- outbound text messages
- outbound image/file messages
- outbound plot messages for FHEM SVG devices

## Features
- FHEM module `98_MatrixBridge.pm`
- password login against the Matrix Client API
- token caching in a local token file
- sending plain text and notice messages
- image/file upload to Matrix
- plot sending for FHEM SVG plot devices via `sendPlot`
- room alias mapping (`me`, `all`, etc. to Matrix room IDs)
- usable with plain Matrix rooms or with bridged rooms such as mautrix-whatsapp portal rooms

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
- prepare a clean GitHub repository with license and issue template
- inventory and remove remaining legacy `Signalbot` leftovers from the live FHEM config
- optionally add inbound Matrix command handling later
