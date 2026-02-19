// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_navigator_observer.dart

import 'package:flutter/material.dart';

import '../models/recording_models.dart';
import 'recording_service.dart';

/// Route name assigned to the root game page.
const String kRouteGamePage = '/gamePage';

/// [NavigatorObserver] that automatically records [navigationAction] events
/// whenever the app pushes or pops a route.
///
/// Register a single instance with [MaterialApp.navigatorObservers] so that
/// all navigation changes are captured without per-call manual hooks.
///
/// The current route name is also exposed via [currentRouteName] so that
/// [RecordingService] can stamp every event with the page it originated from.
class RecordingNavigatorObserver extends NavigatorObserver {
  factory RecordingNavigatorObserver() => _instance;

  RecordingNavigatorObserver._internal();

  static final RecordingNavigatorObserver _instance =
      RecordingNavigatorObserver._internal();

  String _currentRouteName = kRouteGamePage;

  /// The name of the currently active route.
  String get currentRouteName => _currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String name = route.settings.name ?? '/unknown';
    _currentRouteName = name;
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{'page': name, 'action': 'push'},
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String name = previousRoute?.settings.name ?? kRouteGamePage;
    _currentRouteName = name;
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{'page': name, 'action': 'pop'},
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final String name = newRoute?.settings.name ?? kRouteGamePage;
    _currentRouteName = name;
  }
}
