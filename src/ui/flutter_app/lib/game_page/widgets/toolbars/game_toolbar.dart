// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_toolbar.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../experience_recording/models/recording_models.dart';
import '../../../experience_recording/services/diagnostic_reproduction_service.dart';
import '../../../experience_recording/services/recording_service.dart';
import '../../../games/mill/mill_board_transform_actions.dart';
import '../../../games/mill/mill_setup_position_controller.dart';
import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/screenshot_service.dart';
import '../../../shared/widgets/lichess_bottom_bar.dart';
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
