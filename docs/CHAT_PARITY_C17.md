# C17 chat presentation candidate

This is a candidate on the authorized four-tab test branch, not a pixel-perfect or fully validated release. C16 evidence and prior failures remain unchanged.

## Product changes

- A visible private/group conversation suppresses the custom four-tab bar for its own tab. Repeated entry/back uses independent visibility leases; account reset clears them. The composer owns a bottom safe-area inset and keeps the tools above the software keyboard and home indicator.
- Private tools follow attachment, voice, emoji, send order. Group tools follow attachment, emoji, send. Photo/video selection remains available inside attachment menus. Drafts keep their existing account-scoped protected storage. The fixture-store path now actually saves group drafts rather than silently bypassing storage.
- Initial loading, empty conversation and load failure have distinct visible states and explicit read retry. Existing messages are retained on transient failure. Deep-link context failure retries the exact initial target rather than pretending an empty latest timeline succeeded. Send/outbox uncertainty remains separate and never automatically resends.
- Streaming connection/reconnection and synchronization states are visible. Existing backoff remains in place; user retry restarts the stream and read synchronization, not sending.
- `chat.showSenderName` defaults to false, as in the inspected H5 source. A synced H5 registry value can be imported read-only using matching global/server/account scope. Native explicit changes are local, account-scoped, and take precedence over an in-flight import. H5 browser-only unsynced preferences cannot be read from the iOS app. No preference is written back to production H5.
- Chat text now uses the existing selectable rich renderer with custom/animated emoji support and content-fitting width. Link cards appear outside unrecalled bubbles, with safe original destinations, bounded metadata/artwork and explicit failure fallback. The detailed MFM subset and unsupported syntax are in `CHAT_CONTENT_SUPPORT.md`.
- The separately reviewed world-feed still-preview/video-poster commit is included. Its validation limits remain in `WORLD_FEED_PERFORMANCE.md`.

## Evidence discipline

- `chat-h5-source-manifest.json` hashes the inspected source snapshot. Its upstream commit and exact deployment equivalence are not established.
- `scripts/h5-chat` renders actual public H5 bundles against `ChatParity.json` using isolated endpoints. Browser network requests outside the local fixture origin are rejected; only the Python server fetches allowed public static assets. It does not log into or write production data. HTML and loaded bundle hashes are retained in the runtime report.
- A failed page capture is named `DIAGNOSTIC-NOT-PARITY`, never counted as a successful comparison. Desktop browser focus is not evidence of an iOS software keyboard. The expected large viewport is 440×956, but the native runner's actual device record must be checked before pairing.
- New presentation tests are isolated from the existing nine chat-alignment methods to preserve their original 30-minute budget. Existing navigation, five legacy regressions, OCR, core tests and raw screenshot/result gates remain required for the formal package. The trial IPA is still explicitly QA-INCOMPLETE until every required gate is proven.
- First local review caught and corrected the synthetic group draft bypass, a deep-link failure/empty-state bug and rich text taking the entire proposed width. This is static self-review, not runtime proof.

## Current limitations before CI

Local Python/Node checks have run; no Swift or Xcode is installed in the Linux editor. Native builds, actual large/small light/dark keyboard screenshots, animated-frame behavior, same-data comparison, live reconnect/load failure integration and media performance traces must be reported from their actual results. Local Chromium could not open its sockets in this executor; no successful local H5 screenshot was produced. The isolated browser job is a second execution path, not a claimed success.

Do not claim all 179 legacy methods, real-device camera/microphone/photos permissions, APNs, minimum iOS17, signed installation/upgrades, 32 complete paired screenshot scenarios, or a numeric 1:1 score. They are not established by adding code or tests.
