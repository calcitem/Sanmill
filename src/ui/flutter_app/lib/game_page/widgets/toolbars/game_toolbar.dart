// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_toolbar.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../generated/intl/l10n.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/services/screenshot_service.dart';
import '../../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../services/annotation/annotation_manager.dart';
import '../../services/mill.dart';
import '../../services/transform/transform.dart';

part 'src/annotation_toolbar.dart';
part 'src/game_page_toolbar.dart';
part 'src/item_theme.dart';
part 'src/item_theme_data.dart';
part 'src/setup_position_toolbar.dart';
part 'src/toolbar_item.dart';
