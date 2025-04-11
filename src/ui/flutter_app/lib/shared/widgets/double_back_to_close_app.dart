// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// double_back_to_close_app.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef WillBackCall = bool Function();

/// Allows the user to close the app by double tapping the back-button.
///
/// You must specify a [SnackBar], so it can be shown when the user taps the
/// back-button.
///
/// Since the back-button is an Android feature, this Widget is going to be
/// nothing but the own [child] if the current platform is anything but Android.
class DoubleBackToCloseApp extends StatefulWidget {
  /// Creates a widget that allows the user to close the app by double tapping
  /// the back-button.
  const DoubleBackToCloseApp({
    super.key,
    required this.snackBar,
    required this.child,
    this.willBack,
  });

  /// The [SnackBar] shown when the user taps the back-button.
  final SnackBar snackBar;

  /// The widget below this widget in the tree.
  final Widget child;

  /// Return false to ignore the component processing, return true to continue
  final WillBackCall? willBack;

  @override
  State<DoubleBackToCloseApp> createState() => _DoubleBackToCloseAppState();
}

class _DoubleBackToCloseAppState extends State<DoubleBackToCloseApp> {
  /// Completer that gets completed whenever the current snack-bar is closed.
  Completer<SnackBarClosedReason> _closedCompleter =
      Completer<SnackBarClosedReason>()..complete(SnackBarClosedReason.remove);

  /// Returns whether the current platform is Android.
  bool get _isAndroid => Theme.of(context).platform == TargetPlatform.android;

  /// Returns whether the [DoubleBackToCloseApp.snackBar] is currently visible.
  bool get _isSnackBarVisible => !_closedCompleter.isCompleted;

  /// Returns whether the next back navigation of this route will be handled
  /// internally.
  ///
  /// Returns true when there's a widget that inserted an entry into the
  /// local-history of the current route, in order to handle pop. This is done
  /// by [Drawer], for example, so it can close on pop.
  bool get _willHandlePopInternally =>
      ModalRoute.of(context)?.willHandlePopInternally ?? false;

  @override
  Widget build(BuildContext context) {
    assert(() {
      _ensureThatContextContainsScaffold();
      return true;
    }());

    if (_isAndroid) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: _handleWillPop,
        child: widget.child,
      );
    } else {
      return widget.child;
    }
  }

  /// Handles [PopScope.onPopInvokedWithResult].
  Future<bool> _handleWillPop(bool didPop, dynamic result) async {
    if (didPop) {
      return false;
    }

    if (widget.willBack != null && !widget.willBack!.call()) {
      return false;
    }

    if (_isSnackBarVisible || _willHandlePopInternally) {
      SystemNavigator.pop();
      return true;
    } else {
      final ScaffoldMessengerState scaffoldMessenger =
          ScaffoldMessenger.of(context);
      scaffoldMessenger.hideCurrentSnackBar();
      _closedCompleter = scaffoldMessenger
          .showSnackBar(widget.snackBar)
          .closed
          .wrapInCompleter();
      return false;
    }
  }

  /// Throws a [FlutterError] if this widget was not wrapped in a [Scaffold].
  void _ensureThatContextContainsScaffold() {
    if (Scaffold.maybeOf(context) == null) {
      throw FlutterError(
        '`DoubleBackToCloseApp` must be wrapped in a `Scaffold`.',
      );
    }
  }
}

extension<T> on Future<T> {
  /// Returns a [Completer] that allows checking for this [Future]'s completion.
  ///
  /// See https://stackoverflow.com/a/69731240/6696558.
  Completer<T> wrapInCompleter() {
    final Completer<T> completer = Completer<T>();
    then(completer.complete).catchError(completer.completeError);
    return completer;
  }
}
