// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_models.dart
//
// This file aggregates all puzzle-related models.

library puzzle_models;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../generated/intl/l10n.dart';

// Export adapters
export 'puzzle_adapters.dart';

// Export rule variant and collection models
export 'rule_schema_version.dart';
export 'rule_variant.dart';
export 'puzzle_collection.dart';

part 'puzzle_category.dart';
part 'puzzle_difficulty.dart';
part 'puzzle_info.dart';
part 'puzzle_progress.dart';
part 'puzzle_settings.dart';
part 'puzzle_models.g.dart';
