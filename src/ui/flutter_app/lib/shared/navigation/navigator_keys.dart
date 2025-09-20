// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// navigator_keys.dart

import 'dart:io';

import 'package:catcher_2/core/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/environment_config.dart';

final GlobalKey<NavigatorState> navigatorStateKey =
    GlobalKey<NavigatorState>();

GlobalKey<NavigatorState> get currentNavigatorKey {
  if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
    return Catcher2.navigatorKey ?? navigatorStateKey;
  }

  return navigatorStateKey;
}
