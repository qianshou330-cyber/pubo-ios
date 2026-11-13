# Chat text and URL cards: explicit support boundary

This change is a native subset, not a full MFM renderer or a verified pixel-perfect copy.

## Reference provenance

Read-only source snapshot under `pubo-h5-reference`, inspected 2026-11-13. Its upstream commit and equality to today's production site have **not** been established. These SHA-256 hashes pin the files actually inspected:

- `packages/frontend/src/pages/chat/XMessage.vue`: `262f056218693b0611522f8e66369ffbb284f620e6fed632e7a7f7b38ae6944a`
- `packages/frontend/src/components/MkUrlPreview.vue`: `5e3439c792dd6a8ccb087dbfb5453c312f40fa76bb86614d74ac44e438ecfb17`
- `packages/frontend/src/utility/extract-url-from-mfm.ts`: `2c28bb9f2491504d902766929d1ee9eaa187c576ed853426b5b593609f6ce111`

H5 places cards outside the bubble, before metadata; its MFM parser extracts ordinary URLs/non-silent links, deduplicates fragments and preserves first occurrence. The native subset implements those rules for simple syntax, with a three-card bound and conservative literal-local-address filtering. This is not a complete URL parser or server-side SSRF defense; server-side DNS/redirect validation is still necessary.

## Support matrix

| Input | Native behavior | Difference / verification requirement |
| --- | --- | --- |
| Plain text, Unicode, line breaks | Selectable TextKit text | Same string; font rasterization/platform layout can differ |
| `**bold**`, `*italic*`, `~~strike~~` | Existing inline Markdown renderer | Not all MFM syntax; formatting crossing emoji-token boundaries can degrade |
| Inline code / fenced code | Existing inline-only renderer; no URL cards inside matched code | Not H5's full block-code layout/highlighter; monospaced code styling is not claimed |
| HTTP(S) text and Markdown links | Validated navigation; native routes for supported PUBO links | Unsafe schemes/embedded credentials are not opened |
| `@handle`, `@handle@host`, `#tag` | Existing native link conversion | H5 hover cards and emoji menu not reproduced |
| `:custom_emoji:` | Existing TextKit inline attachment, animated when available | Unknown tokens remain readable; remote-name syntax `:name@host:` not supported |
| Animated custom emoji | Same bounded image store/decoder as notes | Paused when offscreen, inactive, backgrounded or Reduce Motion; runtime/frame evidence still required |
| `$[spin …]`, `$[shake …]`, math, ruby, complex/nested MFM | No execution; source/inline Markdown fallback | No full MFM compatibility claim; animations and advanced typesetting absent |
| URL card | Title, up to three description lines, site/domain, optional thumbnail; source URL stays the destination | Three cards max; first occurrence/order retained; no embedded iframe/player, tweet expansion, icon, or data-saver setting migration |
| Failed metadata / artwork | Original URL remains actionable, metadata retry button; failed artwork keeps text | A visible fallback, not silent card disappearance |
| Sensitive thumbnail | Omitted when metadata marks `sensitive` | Text/link preserved |

No production requests are made in synthetic UI mode. `--chat-preview-failure` makes the first metadata attempt fail; tapping the card-specific `.retry` control succeeds from synthetic metadata. Ordinary synthetic metadata identifies itself as test data. This does not prove behavior against the production metadata service.

## Lifecycle and resource limits

Metadata fetches are visible/active/foreground gated, canceled by SwiftUI tasks, and guarded against account-generation changes. Responses are not persisted. Card destinations cannot be replaced by metadata redirects. Metadata payloads are capped at 512 KB; HTTPS artwork is capped at 2 MB and decoded to 240 px. Emoji loading reuses the existing bounded store. Links and text keep dynamic semantic colors. Cards have a minimum 44-point opening target and a separate retry control.

## Verification status

Three focused `ChatContentPolicyTests` cover Unicode/token preservation, URL order/fragment deduplication/bounds, and code/silent/unsafe exclusions. They were added but **not executed in the Linux editor**, which has no `swift` executable. `git diff --check` was executed successfully. Compile, core tests, actual keyboard/theme/size screenshots, animated-frame evidence and same-data H5/native visual comparison must be reported separately by the integrating task. Do not treat this document as evidence that those checks passed.
