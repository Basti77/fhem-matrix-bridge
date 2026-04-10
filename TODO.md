# TODO / ROADMAP

## Near term
- [ ] Test and document a clean Signal bridge room model similar to the WhatsApp relay setup.
- [ ] Inventory remaining legacy `Signalbot` usages in the live FHEM config and decide what can be removed.
- [ ] Decide whether image/plot messages should support optional captions or always stay caption-free by default.
- [ ] Add a safer diagnostic mode for media uploads and plot rendering.

## Project hygiene
- [ ] Initialize a dedicated Git repository for this project.
- [ ] Add a license file.
- [ ] Add a minimal README section for contribution workflow.
- [ ] Add example screenshots for text/image/plot delivery.
- [ ] Tag the first public release after one more round of cleanup/testing.

## Functional enhancements
- [x] Add optional inbound Matrix command handling (v0.3.0).
- [ ] Add room discovery helpers so room IDs do not always need to be copied manually.
- [ ] Improve token/session handling beyond simple token cache reuse.
- [ ] Add richer error reporting in FHEM readings for Matrix API/media failures.
- [ ] Consider support for additional message types if needed.

## Hardening / safety
- [ ] Document a recommended permission model for production use.
- [ ] Add guidance for bot-user password rotation.
- [ ] Document backup/restore expectations for Matrix-side room integration.
- [ ] Keep bridge permissions intentionally narrow and room-specific.

## Nice to have
- [ ] Prepare a GitHub-friendly release checklist.
- [ ] Add a CHANGELOG entry template for future releases.
- [ ] Add a small test matrix covering Element mobile, Element desktop, browser, and bridged WhatsApp rendering.
