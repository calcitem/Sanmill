// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// helpers.dart
//
// Shared test utilities for integration tests.
// Provides common operations like navigation, scrolling, and verification
// that are reused across multiple test files.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/shared/services/logger.dart';

/// Default timeout for pump and settle operations.
const Duration kDefaultPumpTimeout = Duration(seconds: 10);

/// Default scroll increment for scrolling through settings lists.
const double kDefaultScrollIncrement = 200.0;

/// Maximum number of scroll attempts before giving up.
const int kMaxScrollAttempts = 30;

/// Large offset used to scroll back to the top of a list.
const double kResetScrollOffset = 10000.0;

// ---------------------------------------------------------------------------
// App Initialization
// ---------------------------------------------------------------------------

/// Pumps the [SanmillApp] widget and waits for it to settle.
///
/// This should be called at the beginning of each test to render the app.
Future<void> initApp(WidgetTester tester) async {
  await tester.pumpWidget(const app.SanmillApp());
  await tester.pumpAndSettle(kDefaultPumpTimeout);
}

// ---------------------------------------------------------------------------
// Drawer Operations
// ---------------------------------------------------------------------------

/// Opens the custom drawer by tapping the drawer overlay button.
Future<void> openDrawer(WidgetTester tester) async {
  final Finder drawerButton = find.byKey(
    const Key('custom_drawer_drawer_overlay_button'),
  );
  expect(drawerButton, findsOneWidget, reason: 'Drawer button should exist');
  await tester.tap(drawerButton);
  await tester.pumpAndSettle();
}

/// Closes the custom drawer by tapping the drawer overlay button again.
Future<void> closeDrawer(WidgetTester tester) async {
  final Finder drawerButton = find.byKey(
    const Key('custom_drawer_drawer_overlay_button'),
  );
  expect(drawerButton, findsOneWidget, reason: 'Drawer button should exist');
  await tester.tap(drawerButton);
  await tester.pumpAndSettle();
}

/// Navigates to a top-level drawer item (non-grouped).
///
/// Opens the drawer, taps the item identified by [itemKey], and waits
/// for the transition to settle.
Future<void> navigateToDrawerItem(WidgetTester tester, String itemKey) async {
  await openDrawer(tester);
  final Finder itemFinder = find.byKey(Key(itemKey));
  expect(itemFinder, findsOneWidget, reason: '$itemKey should be present');
  await tester.tap(itemFinder);
  await tester.pumpAndSettle();
}

/// Navigates to a child item inside a collapsible drawer group.
///
/// Opens the drawer, taps the [groupKey] to expand the group, then taps
/// the [childKey] to navigate to the child page.
Future<void> navigateToGroupChild(
  WidgetTester tester,
  String groupKey,
  String childKey,
) async {
  await openDrawer(tester);

  // Tap the group item to expand it
  final Finder groupFinder = find.byKey(Key(groupKey));
  expect(groupFinder, findsOneWidget, reason: '$groupKey should be present');
  await tester.tap(groupFinder);
  await tester.pumpAndSettle();

  // Tap the child item
  final Finder childFinder = find.byKey(Key(childKey));
  expect(childFinder, findsOneWidget, reason: '$childKey should be present');
  await tester.tap(childFinder);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Scrolling Utilities
// ---------------------------------------------------------------------------

/// Checks whether [target] is "truly tappable" via hit-testing.
///
/// Returns true if the render object of [target] appears in the
/// hit-test path at the widget's center coordinate.
bool isWidgetTappable(WidgetTester tester, Finder target) {
  if (target.evaluate().isEmpty) {
    return false;
  }

  final Offset center = tester.getCenter(target);
  final RenderView rootView = RendererBinding.instance.renderViews.first;
  final BoxHitTestResult result = BoxHitTestResult();
  rootView.hitTest(result, position: center);

  final RenderObject? targetRenderObject = target.evaluate().first.renderObject;
  if (targetRenderObject == null) {
    return false;
  }

  for (final HitTestEntry<dynamic> entry in result.path) {
    if (entry.target == targetRenderObject) {
      return true;
    }
  }
  return false;
}

/// Scrolls a scrollable widget identified by [scrollableKey] until the
/// widget identified by [targetKey] is visible and tappable.
///
/// Optionally resets the scroll position to the top first when
/// [resetScroll] is true.
///
/// Returns true if the widget was found and is tappable.
Future<bool> scrollUntilVisible(
  WidgetTester tester, {
  required String targetKey,
  String scrollableKey = 'settings_list',
  double scrollIncrement = kDefaultScrollIncrement,
  bool resetScroll = true,
}) async {
  final Finder scrollableFinder = find.byKey(Key(scrollableKey));
  final Finder targetFinder = find.byKey(Key(targetKey));

  if (scrollableFinder.evaluate().isEmpty) {
    logger.e('Scrollable "$scrollableKey" not found');
    return false;
  }

  // Reset to top if requested
  if (resetScroll) {
    await tester.drag(scrollableFinder, const Offset(0, kResetScrollOffset));
    await tester.pumpAndSettle();
  }

  // First pass: scroll down
  for (int i = 0; i < kMaxScrollAttempts; i++) {
    if (isWidgetTappable(tester, targetFinder)) {
      return true;
    }
    await tester.drag(scrollableFinder, Offset(0, -scrollIncrement));
    await tester.pumpAndSettle();
  }

  // Second pass: reset and try again
  await tester.drag(scrollableFinder, const Offset(0, kResetScrollOffset));
  await tester.pumpAndSettle();

  for (int i = 0; i < kMaxScrollAttempts; i++) {
    if (isWidgetTappable(tester, targetFinder)) {
      return true;
    }
    await tester.drag(scrollableFinder, Offset(0, -scrollIncrement));
    await tester.pumpAndSettle();
  }

  logger.e('Failed to scroll to target "$targetKey"');
  return false;
}

/// Scrolls to [targetKey] and taps it.
///
/// Asserts that the widget was found after scrolling.
Future<void> scrollToAndTap(
  WidgetTester tester, {
  required String targetKey,
  String scrollableKey = 'settings_list',
  bool resetScroll = true,
}) async {
  final bool found = await scrollUntilVisible(
    tester,
    targetKey: targetKey,
    scrollableKey: scrollableKey,
    resetScroll: resetScroll,
  );
  expect(found, isTrue, reason: '"$targetKey" should be scrollable into view');

  final Finder targetFinder = find.byKey(Key(targetKey));
  expect(targetFinder, findsOneWidget);
  await tester.tap(targetFinder);
  await tester.pumpAndSettle();
}

/// Scrolls to [targetKey] and verifies it is visible.
///
/// Asserts that the widget was found after scrolling.
Future<void> scrollToAndVerify(
  WidgetTester tester, {
  required String targetKey,
  String scrollableKey = 'settings_list',
  bool resetScroll = true,
}) async {
  final bool found = await scrollUntilVisible(
    tester,
    targetKey: targetKey,
    scrollableKey: scrollableKey,
    resetScroll: resetScroll,
  );
  expect(found, isTrue, reason: '"$targetKey" should be scrollable into view');

  final Finder targetFinder = find.byKey(Key(targetKey));
  expect(targetFinder, findsOneWidget);
}

// ---------------------------------------------------------------------------
// Page Verification
// ---------------------------------------------------------------------------

/// Verifies that a page with the given scaffold [scaffoldKey] is displayed.
void verifyPageDisplayed(WidgetTester tester, String scaffoldKey) {
  final Finder scaffold = find.byKey(Key(scaffoldKey));
  expect(scaffold, findsOneWidget, reason: 'Page "$scaffoldKey" should exist');
}

/// Verifies that a widget identified by [key] exists in the widget tree.
void verifyWidgetExists(WidgetTester tester, String key) {
  final Finder widget = find.byKey(Key(key));
  expect(widget, findsOneWidget, reason: 'Widget "$key" should exist');
}

// ---------------------------------------------------------------------------
// Game Operations
// ---------------------------------------------------------------------------

/// Taps a toolbar item identified by [key].
Future<void> tapToolbarItem(WidgetTester tester, String key) async {
  final Finder item = find.byKey(Key(key));
  expect(item, findsOneWidget, reason: 'Toolbar item "$key" should exist');
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Starts a new game from the game page toolbar.
///
/// Taps the Game toolbar item, selects New Game, and confirms if a restart
/// dialog appears. Handles both fresh game (no dialog) and active game
/// (with restart confirmation dialog) scenarios.
Future<void> startNewGame(WidgetTester tester) async {
  // Tap the Game toolbar item to open the game options modal
  await tapToolbarItem(tester, 'play_area_toolbar_item_game');

  // Tap the New Game option
  final Finder newGameOption = find.byKey(const Key('new_game_option'));
  expect(newGameOption, findsOneWidget, reason: 'New Game option should exist');
  await tester.tap(newGameOption);
  await tester.pumpAndSettle();

  // If the restart confirmation dialog appears, tap Yes
  final Finder yesButton = find.byKey(const Key('restart_game_yes_button'));
  if (yesButton.evaluate().isNotEmpty) {
    await tester.tap(yesButton);
    await tester.pumpAndSettle();
  }
}

// ---------------------------------------------------------------------------
// Delay Utility
// ---------------------------------------------------------------------------

/// Waits for a specified [duration] and then pumps the widget tree.
Future<void> delayAndPump(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}
