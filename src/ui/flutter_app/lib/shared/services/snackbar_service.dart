// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// snackbar_service.dart

import 'package:flutter/material.dart';

import '../widgets/snackbars/scaffold_messenger.dart';
import 'logger.dart';

/// Service to handle global SnackBar display throughout the application
class SnackBarService {
  // Private constructor to prevent instantiation
  SnackBarService._();

  /// Show a SnackBar with the given message using the root scaffold messenger
  ///
  /// This method provides safe access to the global SnackBar system with proper
  /// null checking and error handling. It automatically clears any existing
  /// SnackBars before showing the new one.
  ///
  /// [message] The text message to display in the SnackBar
  /// [duration] Optional duration for the SnackBar (uses default if not specified)
  static void showRootSnackBar(String message, {Duration? duration}) {
    final ScaffoldMessengerState? messenger =
        rootScaffoldMessengerKey.currentState;

    if (messenger == null) {
      // During early startup the scaffold messenger might not be ready yet
      logger.w(
        'Unable to show SnackBar because the messenger is not ready: '
        '$message',
      );
      return;
    }

    if (duration != null) {
      // Clear existing SnackBars first
      messenger.clearSnackBars();
      messenger.showSnackBar(CustomSnackBar(message, duration: duration));
    } else {
      // Use the extension method which handles clearing automatically
      messenger.showSnackBarClear(message);
    }
  }

  /// Show a SnackBar with custom SnackBar widget
  ///
  /// This method allows showing custom SnackBar widgets while still providing
  /// safe access and proper error handling.
  ///
  /// [snackBar] The custom SnackBar widget to display
  static void showCustomSnackBar(SnackBar snackBar) {
    final ScaffoldMessengerState? messenger =
        rootScaffoldMessengerKey.currentState;

    if (messenger == null) {
      logger.w(
        'Unable to show custom SnackBar because the messenger is not ready',
      );
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
  }

  /// Clear all currently displayed SnackBars
  ///
  /// This method safely clears any existing SnackBars from the root scaffold messenger.
  static void clearSnackBars() {
    final ScaffoldMessengerState? messenger =
        rootScaffoldMessengerKey.currentState;

    if (messenger != null) {
      messenger.clearSnackBars();
    }
  }

  /// Get the current context from the root scaffold messenger
  ///
  /// This is useful for accessing localization or other context-dependent resources
  /// when showing SnackBars from services or other non-widget code.
  ///
  /// Returns null if the messenger is not ready or has no context.
  static BuildContext? get currentContext {
    return rootScaffoldMessengerKey.currentContext;
  }
}
