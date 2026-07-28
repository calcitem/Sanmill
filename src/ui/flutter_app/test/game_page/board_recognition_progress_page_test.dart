// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/pages/board_recognition_progress_page.dart';

void main() {
  testWidgets('runs work after showing an opaque progress page', (
    WidgetTester tester,
  ) async {
    final Completer<int> task = Completer<int>();
    BoardRecognitionProgressResult<int>? received;
    bool progressWasVisibleWhenTaskStarted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  received = await showBoardRecognitionProgress<int>(
                    context: context,
                    message: 'Analyzing board',
                    task: () {
                      progressWasVisibleWhenTaskStarted = find
                          .byKey(const Key('board_recognition_progress_page'))
                          .evaluate()
                          .isNotEmpty;
                      return task.future;
                    },
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();

    final Finder progressPage = find.byKey(
      const Key('board_recognition_progress_page'),
    );
    expect(progressPage, findsOne);
    expect(progressWasVisibleWhenTaskStarted, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOne);
    expect(find.text('Analyzing board'), findsOne);

    final ModalRoute<dynamic> route = ModalRoute.of(
      tester.element(progressPage),
    )!;
    expect(route.opaque, isTrue);
    expect(route.barrierColor, isNull);

    task.complete(7);
    await tester.pumpAndSettle();

    expect(progressPage, findsNothing);
    expect(received?.isSuccess, isTrue);
    expect(received?.value, 7);
  });

  testWidgets('uses the root navigator above the application shell', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> rootNavigatorKey =
        GlobalKey<NavigatorState>();
    final GlobalKey<NavigatorState> nestedNavigatorKey =
        GlobalKey<NavigatorState>();
    final Completer<void> task = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: Scaffold(
          body: Navigator(
            key: nestedNavigatorKey,
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => Center(
                    child: FilledButton(
                      onPressed: () => showBoardRecognitionProgress<void>(
                        context: context,
                        message: 'Analyzing board',
                        task: () => task.future,
                      ),
                      child: const Text('Start'),
                    ),
                  ),
                ),
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'More'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(
      find.byKey(const Key('board_recognition_progress_page')),
      findsOneWidget,
    );
    expect(find.text('Home'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(rootNavigatorKey.currentState!.canPop(), isTrue);
    expect(nestedNavigatorKey.currentState!.canPop(), isFalse);

    task.complete();
    await tester.pumpAndSettle();

    expect(rootNavigatorKey.currentState!.canPop(), isFalse);
    expect(nestedNavigatorKey.currentState!.canPop(), isFalse);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });
}
