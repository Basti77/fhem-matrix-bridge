# Changelog

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
