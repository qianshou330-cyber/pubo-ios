"""Explicit, disjoint UI shards. A timeout or skipped test is never a pass."""
SHARDS = {
    'social-actions': (22, [
        'SocialAlignmentUITests', 'ParityBatchUITests', 'FollowRequestParityUITests',
        'FollowListParityUITests', 'ContactPagingParityUITests',
        'LocalTimelineUITests/testOlderFailureRetriesAtReadingPositionWithoutDroppingPosts',
    ]),
    'social-settings': (9, [
        'AccountSettingsParityUITests', 'ProfileParityUITests', 'DriveParityUITests', 'ChannelParityUITests',
    ]),
    'authentication': (9, ['AuthStaticUITests']),
    'baseline': (46, ['PUBOUITests']),
    # Independent synthetic expansion; original 86 and focused five remain unchanged.
    'chat-alignment': (9, ['ChatAlignmentUITests']),
}
FOCUSED = [
    'PUBOUITests/testAHomePullRefreshAndForegroundRefreshWithoutHeaderButtons',
    'PUBOUITests/testHomePanelsAndChartNavigation',
    'PUBOUITests/testNativePrivacyAndVerificationStatus',
    'PUBOUITests/testChatEditConflictAndLostResponseKeepDraftUntilManualResolution',
    'AccountSettingsParityUITests/testAutoAcceptRequiresLockedAccountAndRetainsSelectionInBothThemes',
]

def selection(shard):
    if shard not in SHARDS:
        raise ValueError('Unknown UI shard: ' + shard)
    count, suites = SHARDS[shard]
    return count, ['-only-testing:PUBOUITests/' + item for item in suites]

def complete(summary, expected):
    return (summary.get('passedTests') == expected and summary.get('failedTests') == 0
            and summary.get('skippedTests') == 0 and summary.get('expectedFailures') == 0)
