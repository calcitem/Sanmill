// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Central semantic route state shared by every Navigator observer.
class DiagnosticRouteTracker {
  const DiagnosticRouteTracker._();

  static final Map<String, List<String>> _stacks = <String, List<String>>{
    'root': <String>['/gamePage'],
  };
  static String _activeNavigatorId = 'root';

  static String get currentRouteId {
    final List<String>? active = _stacks[_activeNavigatorId];
    if (active != null && active.isNotEmpty) {
      return active.last;
    }
    final List<String>? root = _stacks['root'];
    return root == null || root.isEmpty ? '/gamePage' : root.last;
  }

  static List<String> get routeStack {
    final List<String> result = <String>[];
    final List<String> navigatorIds = _stacks.keys.toList()..sort();
    for (final String navigatorId in navigatorIds) {
      for (final String route in _stacks[navigatorId]!) {
        result.add('$navigatorId:$route');
      }
    }
    return List<String>.unmodifiable(result);
  }

  static void activateNavigator(String navigatorId) {
    _stacks.putIfAbsent(navigatorId, () => <String>['/gamePage']);
    _activeNavigatorId = navigatorId;
  }

  static void push(String navigatorId, String routeId) {
    _activeNavigatorId = navigatorId;
    _stacks.putIfAbsent(navigatorId, () => <String>[]).add(routeId);
  }

  static void pop(String navigatorId, String routeId) {
    _activeNavigatorId = navigatorId;
    final List<String> stack = _stacks.putIfAbsent(
      navigatorId,
      () => <String>[],
    );
    if (stack.isNotEmpty) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      stack.add(routeId);
    }
  }

  static void replace(String navigatorId, String routeId) {
    _activeNavigatorId = navigatorId;
    final List<String> stack = _stacks.putIfAbsent(
      navigatorId,
      () => <String>[],
    );
    if (stack.isNotEmpty) {
      stack[stack.length - 1] = routeId;
    } else {
      stack.add(routeId);
    }
  }

  static void remove(String navigatorId, String fallbackRouteId) {
    pop(navigatorId, fallbackRouteId);
  }
}
