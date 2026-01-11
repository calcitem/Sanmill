// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// scaffold_messenger.dart

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension ScaffoldMessengerExtension on ScaffoldMessengerState {
  void showSnackBarClear(String message) {
    // Clearing this messenger instance covers both the root key and any
    // nested scaffold messengers that invoke the helper.
    clearSnackBars();

    showSnackBar(CustomSnackBar(message));
  }
}

class CustomSnackBar extends SnackBar {
  CustomSnackBar(String message, {super.key, super.duration})
    : super(content: Text(message));
}
