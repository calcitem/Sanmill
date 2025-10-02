// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.dart

import 'package:logger/logger.dart';

import 'environment_config.dart';

int _clampLogLevel(int requested) {
  if (requested < 0) {
    return 0;
  }
  if (requested >= Level.values.length) {
    return Level.values.length - 1;
  }
  return requested;
}

final Logger logger = Logger(
  level: Level.values[_clampLogLevel(EnvironmentConfig.logLevel)],
);
