# Build143 candidate: Drive disclosure and selection

Reference: verified Oct31 H5 source, `components/MkDrive.file.vue` and `utility/get-drive-file-menu.ts`. H5 marks sensitive files but does not permanently remove download/selection actions. This is source-based parity, not a claim of live pixel identity.

## Changes
- Drive file manager no longer permanently disables preview for sensitive files. It first re-reads `drive/files/show` and validates the ID, then asks explicit confirmation before loading sensitive bytes. Cancel loads no preview; closing and reopening asks again. Account changes close the sheet.
- File picker re-reads the chosen file by ID and rechecks MIME/sensitivity before selecting; it cancels in-flight selection on dismissal/account change. It allows sensitive images after a separate warning; confirms possible public exposure for avatar/banner use, preserves the server flag, and guards duplicate selection. Image-only mode still rejects non-images regardless of server filtering.
- Profile editor receives sensitive consent via a separate callback emitted only by the confirmed picker path. Ordinary selection/upload does not acquire blanket consent. No profile save is automated by choosing a file.
- Picker validates response arrays instead of converting malformed data to a misleading empty list; cancellation is not shown as an error.

## Tests and boundaries
- `DriveMediaPolicyTests`: explicit sensitivity gate and image MIME eligibility.
- `DriveParityUITests`: synthetic-only cancel/confirm/reopen both themes, stale non-sensitive list vs fresh sensitive metadata, and image picker consent/cancel/draft paths for both already-sensitive and stale non-sensitive list entries. No production calls or local file/photo saves.
- Fixture flags `--drive-sensitive-preview` and `--drive-sensitive-late` use a known bundled still image via the DEBUG media path.
- Linux cannot compile/run SwiftUI. Tests must be added to the next Mac CI batch and results inspected before claiming pass.
- Existing 50 MiB limits, safeMediaURL validation, temporary-file protection/cleanup and explicit save actions remain.
- Did not change production H5, private chat attachment protections, server sensitive flag, or upload any user files. No push, main merge, PR or release from this subtask.
