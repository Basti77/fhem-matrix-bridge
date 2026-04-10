# Changelog

## 0.4.0 - 2026-04-10
- Fixed plot display on mobile Matrix clients (Element X / Android): images were cropped to a center section because width/height metadata was missing from the Matrix image event. The module now reads PNG dimensions from the file header and sends `w`/`h` in the `m.image` info object.
- Fixed plot display on Element Desktop: axis labels and plot title were missing because `Image::LibRSVG` (Perl) has known issues with complex CSS selectors in FHEM SVG output. The module now prefers `rsvg-convert` (CLI) for SVG-to-PNG conversion, which renders text and CSS correctly. Falls back to `plotAsPng` if `rsvg-convert` is not installed.
- Fixed `sendPlot` ignoring the caption parameter — captions are now passed through to the Matrix image message.
- New system dependency: `librsvg2-bin` (recommended, for correct plot rendering).

## 0.3.0 - 2026-04-10
- Added inbound Matrix message handling via `/sync` Long-Polling.
- New attributes: `botKeyword`, `allowedUsers`, `exposeRoom`, `allowRawCmds`, `syncEnabled`, `syncInterval`.
- New commands: `set startSync`, `set stopSync`.
- Bot responds only to messages starting with configurable keyword (e.g. `@fhem`).
- User whitelist via `allowedUsers` attribute for access control.
- `list` command: lists all devices in the configured `exposeRoom` with alias and state.
- Device control via alias: e.g. `@fhem Wohnzimmerlampe on`.
- Optional raw FHEM command passthrough via `cmd` prefix (requires `allowRawCmds 1`).
- Persistent `since` token for sync position — no duplicate messages after restart.
- New readings: `syncState`, `lastInboundSender`, `lastInboundRoom`, `lastInboundMessage`.
- Sync starts automatically after login when `syncEnabled` is set.

## 0.2.0 - 2026-03-15
- Added Matrix media upload support for image messages.
- Added `sendImage` for local file uploads.
- Added `sendPlot` for FHEM SVG plot devices using the local PNG rendering path.
- Fixed UTF-8 handling for text messages containing emojis and non-ASCII characters.
- Improved image event handling so picture messages render correctly across more Matrix clients.
- Generalized docs and examples to avoid personal domains, passwords, usernames, and room IDs.
- Documented required Perl/system libraries and the WhatsApp relay permission setup.
- Added notes for follow-up work (Signal bridge, GitHub sync, cleanup of legacy Signalbot leftovers).

## 0.1.0 - 2026-03-15
- Initial project scaffold.
- Added standalone FHEM module `98_MatrixBridge.pm` for sending Matrix messages.
- Supports password login, token caching, room aliases, simple `set send` command, and basic readings.
- Added installation and usage documentation.
