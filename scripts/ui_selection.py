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
    'chat-presentation': (8, ['ChatComposerParityUITests']),
}
FOCUSED = [
    'PUBOUITests/testAHomePullRefreshAndForegroundRefreshWithoutHeaderButtons',
    'PUBOUITests/testHomePanelsAndChartNavigation',
    'PUBOUITests/testNativePrivacyAndVerificationStatus',
    'PUBOUITests/testChatEditConflictAndLostResponseKeepDraftUntilManualResolution',
    'AccountSettingsParityUITests/testAutoAcceptRequiresLockedAccountAndRetainsSelectionInBothThemes',
]

# The complete eight-method selection stays available. CI splits it into two
# disjoint four-method jobs so runner startup cannot consume the whole 30-minute
# budget before later methods start. Both halves are required for each size.
PRESENTATION_PARTS = {
    'chat-presentation-composer': [
        'testPrivateComposerToolsAndBackRestoreBothThemes',
        'testRoomComposerToolsAndBackRestoreBothThemes',
        'testPrivateKeyboardAndDraftSurviveBackBothThemes',
        'testRoomKeyboardAndDraftSurviveBackBothThemes',
    ],
    'chat-presentation-states': [
        'testInitialLoadingAndEmptyConversationStates',
        'testInitialFailureHasExplicitRetryAndRecovers',
        'testRoomSenderNamesRespectSyncedPreference',
        'testLinkPreviewFailurePreservesDestinationAndRetries',
    ],
}

def selection(shard):
    if shard in PRESENTATION_PARTS:
        methods = PRESENTATION_PARTS[shard]
        return len(methods), ['-only-testing:PUBOUITests/ChatComposerParityUITests/' + name for name in methods]
    if shard not in SHARDS:
        raise ValueError('Unknown UI shard: ' + shard)
    count, suites = SHARDS[shard]
    return count, ['-only-testing:PUBOUITests/' + item for item in suites]

def complete(summary, expected):
    return (summary.get('passedTests') == expected and summary.get('failedTests') == 0
            and summary.get('skippedTests') == 0 and summary.get('expectedFailures') == 0)
