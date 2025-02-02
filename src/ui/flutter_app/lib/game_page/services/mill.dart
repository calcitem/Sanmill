// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/assets/assets.gen.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/native_methods.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/utils/helpers/array_helpers/array_helper.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/utils/helpers/string_helpers/string_helper.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import 'animation/animation_manager.dart';
import 'engine/bitboard.dart';
import "gif_share/gif_share.dart";
import 'import_export/import_helpers.dart';
import 'import_export/pgn.dart';

part 'controller/game_controller.dart';
part 'controller/game_recorder.dart';
part 'controller/game_responses.dart';
part 'controller/history_navigation.dart';
part 'controller/tap_handler.dart';
part 'engine/engine.dart';
part 'engine/ext_move.dart';
part 'engine/game.dart';
part 'engine/mills.dart';
part 'engine/opening_book.dart';
part 'engine/position.dart';
part 'engine/types.dart';
part 'engine/zobrist.dart';
part 'import_export/export_service.dart';
part 'import_export/import_exceptions.dart';
part 'import_export/import_service.dart';
part 'import_export/notation_parsing.dart';
part 'notifiers/board_semantics_notifier.dart';
part 'notifiers/game_result_notifier.dart';
part 'notifiers/header_icons_notifier.dart';
part 'notifiers/header_tip_notifier.dart';
part 'notifiers/setup_position_notifier.dart';
part 'save_load/save_load_service.dart';
part 'sounds/sound_manager.dart';
part 'sounds/vibration_manager.dart';
part "transform/transform.dart";

// TODO: [Leptopoda] Separate the ui from the logic
