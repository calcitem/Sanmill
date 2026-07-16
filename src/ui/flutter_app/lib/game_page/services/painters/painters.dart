// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// painters.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../appearance_settings/models/color_settings.dart';
import '../../../appearance_settings/models/display_settings.dart';
import '../../../game_platform/game_session.dart';
import '../../../games/mill/mill_board_coordinate_maps.dart';
import '../../../games/mill/native_mill_snapshot_board_view.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/environment_config.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/utils/helpers/color_helpers/color_helper.dart';
import '../analysis_mode.dart';
import '../mill.dart';
import 'animations/piece_effect_animation.dart';
import 'piece.dart';

part 'analysis_renderer.dart';
part 'board_painter.dart';
part 'board_utils.dart';
part 'piece_painter.dart';
