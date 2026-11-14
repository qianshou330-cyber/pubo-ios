# C31 isolated reconstruction: chat menus and deletion intent

This is a new reconstruction from the verified C30 source tree (remote
47190f3f1a25821954e5fe8d4b59743c56e4b5c0). It is **not** recovery of the missing
14e2133 candidate. C30 CI must finish before any publication of this batch.

## Changes

- A shared action list feeds bubble context menus, overflow menus and the
  UITextView edit menu in private and room chats. UIKit suggested selection
  actions and link handling remain intact.
- Action execution rechecks account/generation, active foreground context and
  current message version. Old menu closures are not treated as revoked merely
  because the coordinator action array was cleared.
- Room-message deletion confirmation is bound to account, generation, screen,
  room and message. Confirmation is consumed before starting an async task;
  the task rechecks before transmission. Results/errors/defer are request-bound.
- A successful delete updates the original list only, rather than starting a
  trailing load after a context switch. Already-transmitted server operations
  cannot be recalled by navigating away.

## Verification boundaries

- Added seven PUBOCore intent tests. They require Mac Swift execution; the
  current Linux workspace has no Swift compiler.
- Added a tenth chat UI test for actual text long press, cancel retaining the
  message, confirmation removing it, and foreign-message report context in
  light/dark mode. Existing bubble long press remains with its five-second
  expectation; query accepts Button or MenuItem to support both menu renderers.
- UIKit confirmation dismissal/action ordering must pass the real UI test.
  Source inspection alone does not prove that confirming deletion works.
- Selection-range copy, links, private-chat menu runtime, switch-account during
  confirmation, repeated taps and delayed responses still need runtime QA.
- No new screenshots, IPA or functional parity score exist for this batch yet.
  Simulator results are not evidence of physical-iPhone performance.
