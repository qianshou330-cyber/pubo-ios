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
    'chat-alignment': (10, ['ChatAlignmentUITests']),
    'chat-presentation': (8, ['ChatComposerParityUITests']),
    'video-poster': (4, ['PublicVideoPosterUITests']),
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


# Exhaustive, disjoint 5+5 alignment selections. No assertions/animations change.
ALIGNMENT_PARTS = {
    'chat-alignment-layout': [
        'testAnimatedReactionKeepsRatioAndPlaysAtLargeTextSize',
        'testGroupDraftSurvivesTabsAndKeyboard',
        'testLargeTextGroupComposerAndTabsStayReachable',
        'testMixedConversationsAndHomeTabsBothThemes',
        'testPrivateSearchDateAndReactionsBothThemes',
    ],
    'chat-alignment-actions': [
        'testGroupSearchExactMessageReportAndMenuBothThemes',
        'testTextSelectionMenuPreservesRoomActionsBothThemes',
        'testGroupReactionDoesNotUseDirectMessagePermission',
        'testReportUnknownOutcomeDisablesResubmission',
        'testStaleOtherParticipantReactionCannotCancelExistingMine',
    ],
}

PRIVATE_BACK_DIAGNOSTICS = {
    'private-back-without-picker': 'testDarkPrivateSecondNativeBackWithoutPicker',
    'private-back-after-picker': 'testDarkPrivateSecondNativeBackAfterPicker',
}

ROOM_BACK_DIAGNOSTICS = {
    'room-back-without-picker': 'testLightRoomSecondNativeBackWithoutPicker',
    'room-back-after-picker': 'testLightRoomSecondNativeBackAfterPicker',
}

WORLD_SCROLL_DIAGNOSTICS = {
    'world-scroll-cross-page': 'testSyntheticWorldCrossPageAndReadingPosition',
    'world-scroll-signposts': 'testSyntheticWorldScrollSignpostSamples',
}

ROOM_MENU_AB_SHARD = 'room-menu-ab'
ROOM_MENU_AB_SUITE = 'RoomMenuABDiagnosticUITests'
ROOM_MENU_AB_METHODS = {'text': 'test01OwnText', 'padding': 'test02OwnBubblePadding'}


def selection(shard):
    if shard == ROOM_MENU_AB_SHARD:
        return len(ROOM_MENU_AB_METHODS), ['-only-testing:PUBOUITests/' + ROOM_MENU_AB_SUITE + '/' + name
                                          for name in ROOM_MENU_AB_METHODS.values()]
    if shard in WORLD_SCROLL_DIAGNOSTICS:
        return 1, ['-only-testing:PUBOUITests/WorldScrollDiagnosticUITests/' + WORLD_SCROLL_DIAGNOSTICS[shard]]
    if shard in ROOM_BACK_DIAGNOSTICS:
        return 1, ['-only-testing:PUBOUITests/RoomNativeBackIsolationUITests/' + ROOM_BACK_DIAGNOSTICS[shard]]
    if shard in PRIVATE_BACK_DIAGNOSTICS:
        return 1, ['-only-testing:PUBOUITests/PrivateNativeBackIsolationUITests/' + PRIVATE_BACK_DIAGNOSTICS[shard]]
    if shard in ALIGNMENT_PARTS:
        methods = ALIGNMENT_PARTS[shard]
        return len(methods), ['-only-testing:PUBOUITests/ChatAlignmentUITests/' + name for name in methods]
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
