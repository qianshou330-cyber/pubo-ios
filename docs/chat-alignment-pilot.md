# Chat-alignment expansion pilot (execution pending)

This change selects the existing nine ChatAlignmentUITests on small and large simulators. It changes no product code, Swift tests, fixtures or runner behavior, and starts no backend. Static tests do not constitute an iOS pass.

Original ui_selection shards remain social-actions22, social-settings9, authentication9 and baseline46 (86 total). A disjoint chat-alignment9 shard raises that registry to95. The existing four-tab13 and focused legacy5 jobs are unchanged. The workflow therefore selects27 unique methods per size (54 size-specific executions), NOT179 methods or full product coverage.

Chat jobs depend only on core checks so OCR preflight failure cannot prevent independent chat evidence. They use PUBO_UI_SHARD=chat-alignment and PUBO_PREBUILT_TESTS=1 with the existing30-minute test budget and65-minute job budget. Each size must have exactly9 passed, zero failed/skipped/expected failures, and successful xcodebuild. No retries, skip selectors, altered confidence thresholds or relaxed assertions are added. Existing focused lifecycle proof and navigation pixel/AX gates remain unchanged.

Formal package now additionally requires chat-alignment, while still requiring checks, OCR validation, navigation and legacy regression. Candidate package remains independently QA-INCOMPLETE under its existing checks/build/package conditions. Chat jobs preserve raw combined stdout/stderr, JSON receipts, xcresult and screenshots even after failure. Runtime and result claims must come from those artifacts, not the workflow's Xcode version label.

The unchanged runner also records a synthetic loading-skeleton clip after a successful first-device non-focused shard. That clip is supplementary capture, not a tenth chat test or chat-specific proof; capture failure may fail the job even after all nine chat assertions pass. Report these outcomes separately.

## Later coverage, not enabled by this pilot

At source67edf8ca there are179 UI method declarations:157 synthetic and22 disposable real-backend methods. Real-backend22 includes PUBOIntegrationTests20, ReconnectionUITests1 and opt-in NotificationBackendTests1. Old86 plus new navigation13 cover99; remaining80 comprise58 synthetic and22 backend. Focused5 overlap old86.

The proposed complete disjoint partition is navigation13, focused5, social-actions11+11, social-settings8, authentication9, baseline11+11+11+9, ChatAlignment9, HomeMotion2, LocalTimeline10+5, NotificationAlignment7, NotificationRoute5, PersonalGIF5, PrivateGIF8, TimelineNavigationEvidence2, TimelineVisual5 and real-loopback22. This21-shard plan on two sizes would produce358 executions; it is NOT enabled here.

Before backend expansion, explicitly address its hardcoded runtime/device, enable notifications, enforce all22 exact identities and no skipped/expected-failure tests, preserve fail-closed receipt verification and local disposable-service isolation. Do not start historical workflows blindly: they overlap and use different runtime contracts. Never infer physical camera scanning, real APNs, signed install/upgrade or iOS17 coverage from simulator results. These remain unverified until separately evidenced.
