# Chat presentation verification plan and evidence

This change separates the original `chat-alignment` nine methods from the new
`chat-presentation` eight methods. The original assertions and strict zero-failure,
zero-skip, zero-expected-failure gate remain intact. Both shards use the existing
small/large simulator matrix; no repeated run is counted as additional coverage.

## New native checks

- Private/group, each light/dark: input and all primary controls are onscreen,
  hittable, at least 44 pt in both dimensions, and below rather than over the editor.
  No custom four-tab buttons exist in detail. An actual attachment menu → Drive
  picker → Cancel round trip preserves the conversation. Actual Back restores all
  four tabs; a repeated entry/back cycle catches stale visibility state.
- Private/group, each light/dark: show the actual software keyboard, type a draft,
  assert editor/tools do not cross the keyboard boundary, then Back and re-enter.
  The exact saved draft must remain. The isolated `--four-tabs-drafts` store is
  used, not a test-only bypass of persistence.
- Private/group initial loading → empty state; initial failure → explicit retry
  button → successful message recovery. Errors cannot be counted as an empty
  conversation. Synthetic transport flags affect timeline reads only, preserving
  the home list used to enter detail.
- Private/group link metadata failure retains the original URL, exposes explicit
  retry and recovers the synthetic title/summary. External links are not opened.
- Group sender nickname is absent by default and present when the synchronized
  H5 `chat.showSenderName` registry value is true.

Fixtures: `--chat-load-delay`, `--chat-load-empty`, `--chat-load-fail-once`,
`--chat-sender-names`, `--chat-preview-failure`. They exist only in the DEBUG synthetic transport; they do
not change production APIs or user data. Failure-once is tracked by endpoint so
private and group fail independently. No synthetic send is repeated automatically.

These test cases are written, not yet run in an iOS runtime in this Linux task.
Local selector checks and Python source checks do not establish UI success.
Microphone/camera permissions, physical-device installation, native photo picker,
reconnect interruption, paging errors, long attachments, large-text matrix and
all-tools end-to-end actions require additional explicit evidence. Existing
large-text and media tests remain in the original nine-method shard.

## H5 source and capture provenance

`chat-h5-source-manifest.json` hashes 32 relevant files from the existing local
Vue snapshot. Its Git commit is unconfirmed and equivalence to current live H5 is
unconfirmed. It is evidence of exactly which source was inspected, not proof of
which code the server deployed.

`scripts/h5-chat` captures the actual current public bundled H5 using the same
`ChatParity.json` messages. Syntax checks and server startup succeeded; Chromium
could not launch due to the executor's socket restrictions, including the approved
outside-sandbox attempt. No legitimate H5 chat screenshot has been produced in
this task. Do not repurpose old timeline screenshots as chat comparisons.

True acceptance requires new iOS and H5 captures labelled with commit/asset
hashes, fixture hash, size, theme, wall time and platform; inspect full screenshots
including input tools. H5 desktop focus is not an iOS keyboard screenshot. The
approved native four-tab shell and platform navigation/keyboard differences must
be reported separately from unintentional content/layout differences.
