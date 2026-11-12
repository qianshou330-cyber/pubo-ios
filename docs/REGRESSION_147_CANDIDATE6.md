# Build 147 candidate 6

Candidate5 small rerun: 4/5 passed, zero skipped. Privacy, chat edit, panels and ordinary privacy passed. Pull returned and applied generation 2. Failure at PUBOUITests.swift:375 waiting for cached app.state, while actual failure screenshot shows SpringBoard. Do not label this a lost-refresh defect.

Apple documents XCUIApplication.state is updated asynchronously:
https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/state-swift.property
https://developer.apple.com/documentation/UIKit/about-the-background-execution-sequence

Candidate6 replaces that cached-state assertion with explicit SpringBoard foreground wait and capture. App.activate plus original generation3 assertion remain. Passive fixture-only DEBUG scene counters additionally prove the same process backgrounded, resumed, and applied generation3; the targeted runner fails closed if this proof is absent. This is stronger than only accepting the Home screen or skipping lifecycle checks. Six Python tests cover valid order, missing transitions, restart, malformed/missing capture and missing applied data. No release-side UI/behavior change.

Mac result pending, no IPA produced. Full 86 per-size tests retained. No main/PR/release change. Independent gallery candidate remains unmerged until 147 validated.
