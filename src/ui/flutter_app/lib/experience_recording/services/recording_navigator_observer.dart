// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_navigator_observer.dart

import 'package:flutter/material.dart';

import '../models/recording_models.dart';
import 'diagnostic_route_tracker.dart';
import 'recording_service.dart';

/// Route name assigned to the root game page.
const String kRouteGamePage = '/gamePage';

/// [NavigatorObserver] that automatically records [navigationAction] events
/// whenever the app pushes or pops a route.
///
/// Register one instance per Navigator. All instances publish into the same
/// central route tracker and diagnostic trail.
///
/// The current route name is also exposed via [currentRouteName] so that
/// [RecordingService] can stamp every event with the page it originated from.
class RecordingNavigatorObserver extends NavigatorObserver {
  RecordingNavigatorObserver({this.navigatorId = 'root'});

  String _currentRouteName = kRouteGamePage;

  final String navigatorId;

  /// The name of the currently active route.
  String get currentRouteName => _currentRouteName;

  /// Marks this Navigator as the visible one after a shell-tab change.
  void activate() {
    DiagnosticRouteTracker.activateNavigator(navigatorId);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String name = _semanticRouteId(route);
    _currentRouteName = name;
    DiagnosticRouteTracker.push(navigatorId, name);
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{
        'page': name,
        'action': 'push',
        'navigatorId': navigatorId,
      },
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String name = previousRoute == null
        ? kRouteGamePage
        : _semanticRouteId(previousRoute);
    _currentRouteName = name;
    DiagnosticRouteTracker.pop(navigatorId, name);
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{
        'page': name,
        'action': 'pop',
        'navigatorId': navigatorId,
      },
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String name = previousRoute == null
        ? kRouteGamePage
        : _semanticRouteId(previousRoute);
    _currentRouteName = name;
    DiagnosticRouteTracker.remove(navigatorId, name);
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{
        'page': name,
        'action': 'remove',
        'navigatorId': navigatorId,
      },
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final String name = newRoute == null
        ? kRouteGamePage
        : _semanticRouteId(newRoute);
    _currentRouteName = name;
    DiagnosticRouteTracker.replace(navigatorId, name);
    RecordingService().recordEvent(
      RecordingEventType.navigationAction,
      <String, dynamic>{
        'page': name,
        'action': 'replace',
        'navigatorId': navigatorId,
      },
    );
  }

  static String _semanticRouteId(Route<dynamic> route) {
    final String? name = route.settings.name;
    if (name != null && name.isNotEmpty && name != '/unknown') {
      return name;
    }
    return 'route.${route.runtimeType.toString().toLowerCase()}';
  }
}
