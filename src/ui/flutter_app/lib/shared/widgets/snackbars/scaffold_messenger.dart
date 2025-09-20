// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// scaffold_messenger.dart

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension ScaffoldMessengerExtension on ScaffoldMessengerState {
  void showSnackBarClear(String message) {
    // Clear any queued snack bars on the messenger invoking this helper so the
    // freshly requested message is shown immediately. This intentionally uses
    // `clearSnackBars` on the current state instead of the global
    // `rootScaffoldMessengerKey` to support both root-level and scoped
    // messengers.
    clearSnackBars();

    showSnackBar(CustomSnackBar(message));
  }
}

class CustomSnackBar extends SnackBar {
  CustomSnackBar(String message, {super.key, super.duration})
      : super(content: Text(message));
}
