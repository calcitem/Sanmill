// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_runner.dart

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/logger.dart';

import 'custom_functions.dart';

/// Runs the steps in a single test scenario.
/// It interprets the 'action' field and executes the corresponding test operation.
Future<void> runScenarioSteps(
  WidgetTester tester,
  List<Map<String, String>> steps,
) async {
  for (final Map<String, String> step in steps) {
    final String action = step['action'] ?? '';
    final String keyValue = step['key'] ?? '';
    final String expectation = step['expect'] ?? '';
    final String? expectedText = step['expectedText'];

    // We'll often look for a widget by the 'key' property.
    // (Some actions might need two keys: e.g. a scrollable container + item.)
    final Finder widgetFinder = find.byKey(Key(keyValue));

    switch (action) {
      case 'tap':
        // Verify widget is present
        expect(widgetFinder, findsOneWidget, reason: expectation);
        // Tap the widget
        await tester.tap(widgetFinder);
        await tester.pumpAndSettle();
        break;

      case 'verify':
        // Just verify widget is present
        expect(widgetFinder, findsOneWidget, reason: expectation);
        break;

      case 'verifyTextEquals':
        // Verify the widget is present
        expect(widgetFinder, findsOneWidget, reason: expectation);

        if (expectedText == null) {
          throw Exception(
              'Missing "expectedText" property for verifyTextEquals action.');
        }
        // Check if the widget is a Text widget
        final Text textWidget = tester.widget<Text>(widgetFinder);
        expect(
          textWidget.data,
          equals(expectedText),
          reason: 'Text content does not match the expected text.',
        );
        break;

      case 'verifyTextContains':
        // Verify the widget is present
        expect(widgetFinder, findsOneWidget, reason: expectation);

        if (expectedText == null) {
          throw Exception(
              'Missing "expectedText" property for verifyTextContains action.');
        }
        final Text textWidgetContains = tester.widget<Text>(widgetFinder);
        expect(
          textWidgetContains.data,
          contains(expectedText),
          reason: 'Text content does not contain the expected substring.',
        );
        break;

      case 'enterText':
        // Example for entering text in a TextField
        expect(widgetFinder, findsOneWidget, reason: expectation);

        if (expectedText == null) {
          throw Exception(
              'Missing "expectedText" property for enterText action.');
        }
        await tester.enterText(widgetFinder, expectedText);
        await tester.pumpAndSettle();
        break;

      case 'scrollUntilVisible':
        // Get the key of the scrollable container. If not specified, default to 'settings_list'
        final String scrollableKey = step['scrollable'] ?? 'settings_list';
        final Finder scrollableFinder = find.byKey(Key(scrollableKey));

        // Verify that the scrollable container exists
        if (scrollableFinder.evaluate().isEmpty) {
          throw Exception(
              'scrollUntilVisible action requires a valid "scrollable" finder.');
        }

        // Get the scroll increment for each scroll, defaulting to 200.0
        final double scrollIncrement =
            double.tryParse(step['scrollIncrement'] ?? '200') ?? 200.0;

        // Determine whether to reset the scroll to the top
        final bool resetScroll =
            (step['resetScroll'] ?? 'false').toLowerCase() == 'true';

        // Define a helper function to check if the widget is "truly" tappable
        bool isWidgetTappable(WidgetTester tester, Finder target) {
          // If the target widget does not exist in the tree, return false immediately
          if (target.evaluate().isEmpty) {
            return false;
          }

          // Get the center coordinates of the target widget on the screen
          final Offset center = tester.getCenter(target);

          // Get the RenderView of the testing environment (the entire root node)
          // Note: This is not a RenderBox, but a RenderView
          final RenderView rootView =
              RendererBinding.instance.renderViews.first;

          // Create a BoxHitTestResult, which inherits from HitTestResult
          final BoxHitTestResult boxHitTestResult = BoxHitTestResult();

          // Perform a hitTest at the specified coordinates
          rootView.hitTest(boxHitTestResult, position: center);

          // Get the render object corresponding to the target widget
          final RenderObject? targetRenderObject =
              target.evaluate().first.renderObject;
          if (targetRenderObject == null) {
            return false;
          }

          // If the hit test path contains the render object of the target widget, it means it is tappable
          for (final HitTestEntry entry in boxHitTestResult.path) {
            if (entry.target == targetRenderObject) {
              return true;
            }
          }
          return false;
        }

        // Perform scrolling and check if the target widget is tappable
        Future<bool> performScroll(Finder scrollable, Finder target,
            int maxScrolls, double offset) async {
          for (int i = 0; i < maxScrolls; i++) {
            // Before each scroll, check if the widget is tappable
            if (isWidgetTappable(tester, target)) {
              logger.i(
                  'Target widget is within tappable range, stopping scroll.');
              return true;
            }

            // If not tappable yet, continue scrolling
            await tester.drag(scrollable, Offset(0, offset));
            await tester.pumpAndSettle();

            logger.i('Performed scroll operation number ${i + 1}.');
          }
          return false;
        }

        bool found = false;
        const int maxScrolls = 20; // Maximum number of scrolls per attempt
        const double resetScrollOffset =
            10000.0; // Offset when scrolling back to the top

        // If resetting scroll to the top is required, perform a large downward drag first
        if (resetScroll) {
          logger.i('Performing scroll back to top.');
          await tester.drag(
              scrollableFinder, const Offset(0, resetScrollOffset));
          await tester.pumpAndSettle();
          logger.i('Scrolled back to top.');
        }

        // First attempt: scroll up to find the target widget
        found = await performScroll(
            scrollableFinder, widgetFinder, maxScrolls, -scrollIncrement);

        if (!found) {
          logger.i(
              'Target widget not found on first scroll, scrolling back to top and retrying.');

          // Scroll back to the top
          await tester.drag(
              scrollableFinder, const Offset(0, resetScrollOffset));
          await tester.pumpAndSettle();
          logger.i('Scrolled back to top.');

          // Second attempt: scroll up again to find the target widget
          found = await performScroll(
              scrollableFinder, widgetFinder, maxScrolls, -scrollIncrement);
        }

        if (!found) {
          logger.e('Failed to scroll to the target widget.');
          throw Exception('Failed to scroll to the target widget.');
        }

        // Finally, verify that the target widget is visible (i.e., exists in the tree)
        expect(widgetFinder, findsOneWidget, reason: expectation);

        // You can also add another assertion here, such as calling isWidgetTappable again:
        // assert(isWidgetTappable(tester, widgetFinder), 'Target widget is not tappable');
        break;

      case 'customFunction':
        // Obtain the function name from the 'step' data
        final String? functionName = step['functionName'];
        if (functionName == null || functionName.isEmpty) {
          throw Exception(
              'No function name was specified for the customFunction action.');
        }

        // Retrieve the actual function reference from customFunctionMap
        final Future<void> Function(WidgetTester p1, Map<String, String> p2)?
            customFunc = customFunctionMap[functionName];
        if (customFunc == null) {
          throw Exception(
              'No custom function registered under the name "$functionName".');
        }

        // Execute the custom function, passing along the WidgetTester and the entire step data if needed
        await customFunc(tester, step);

        // Allow any pending animations or rebuilds to complete
        await tester.pumpAndSettle();
        break;

      case 'delay':
        // Handle the 'delay' action
        final String? durationStr = step['duration'];
        if (durationStr == null) {
          throw Exception('Missing "duration" property for delay action.');
        }

        // Parse the duration. You can specify duration in milliseconds, seconds, etc.
        // Here, we'll assume the duration is specified in milliseconds.
        final int? durationMs = int.tryParse(durationStr);
        if (durationMs == null) {
          throw Exception(
              'Invalid "duration" value for delay action. Must be an integer representing milliseconds.');
        }

        // Log the delay
        logger.i('Delaying for $durationMs milliseconds.');

        // Perform the delay
        await Future<void>.delayed(Duration(milliseconds: durationMs));

        // Optionally, you can pump to process any pending frames
        await tester.pump();
        break;

      default:
        throw Exception('Unknown action: $action');
    }
  }
}
