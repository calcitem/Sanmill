// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.dart

import 'package:logger/logger.dart';

import 'environment_config.dart';

final Logger logger = Logger(level: Level.values[EnvironmentConfig.logLevel]);
