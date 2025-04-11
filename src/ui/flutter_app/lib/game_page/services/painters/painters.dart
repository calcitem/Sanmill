// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
import '../../../shared/database/database.dart';
import '../../../shared/services/environment_config.dart';
import '../../../shared/themes/app_theme.dart';
import '../../widgets/board/analysis_renderer.dart';
import '../analysis_mode.dart';
import '../mill.dart';
import 'animations/piece_effect_animation.dart';
import 'piece.dart';

part 'board_painter.dart';
part 'board_utils.dart';
part 'piece_painter.dart';
