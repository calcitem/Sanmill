// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_platform/game_export_service.dart';
import '../../game_platform/game_session.dart';
import '../../games/mill/mill_marked_pieces_codec.dart';
import '../../game_platform/game_session.dart' as platform;
import '../../game_shell/game_session_scope.dart';
import '../../games/mill/lan_session_meta.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/mill_board_coordinate_maps.dart';
import '../../games/mill/mill_session_tap_controller.dart';
import '../../games/mill/native_mill_ai_turn_controller.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../games/mill/native_mill_rules_port.dart';
import '../../games/mill/native_mill_snapshot_board_view.dart';
import '../../games/mill/puzzle_mill_session.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/assets/assets.gen.dart';
import '../../generated/intl/l10n.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/config/prompt_defaults.dart';
import '../../shared/database/database.dart';
import '../../shared/services/catcher_service.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/game_interaction_coordinator.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/native_methods.dart';
import '../../shared/services/system_ui_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/utils/helpers/array_helpers/array_helper.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/utils/helpers/string_helpers/string_helper.dart';
import '../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../src/rust/api/simple.dart' as tgf;
import '../../statistics/services/stats_service.dart';
import '../widgets/dialogs/engine_failure_dialog.dart';
import '../widgets/dialogs/performance_warning_dialog.dart';
import '../widgets/qr_scan_result_dialog.dart';
import 'analysis_mode.dart';
import 'animation/animation_manager.dart';
import 'annotation/annotation_manager.dart';
import 'engine/bitboard.dart';
import "gif_share/gif_share.dart";
import 'import_export/import_helpers.dart';
import 'import_export/pgn.dart';
import 'player_timer.dart';

part 'controller/game_controller.dart';
part 'controller/game_recorder.dart';
part 'controller/game_responses.dart';
part 'controller/history_navigation.dart';
part 'controller/tap_handler.dart';
part 'engine/engine.dart';
part 'engine/ext_move.dart';
part 'engine/game.dart';
part 'engine/board_view.dart';
part 'engine/position.dart';
part 'engine/types.dart';
part 'import_export/export_service.dart';
part 'import_export/import_exceptions.dart';
part 'import_export/import_service.dart';
part 'import_export/notation_parsing.dart';
part "network/network_service.dart";
part 'notifiers/board_semantics_notifier.dart';
part 'notifiers/game_result_notifier.dart';
part 'notifiers/header_icons_notifier.dart';
part 'notifiers/header_tip_notifier.dart';
part 'notifiers/setup_position_notifier.dart';
part 'save_load/save_load_service.dart';
part 'sounds/sound_manager.dart';
part 'sounds/vibration_manager.dart';

/// Move quality evaluation from analysis
enum MoveQuality {
  normal, // Regular move
  minorGoodMove, // Good move (!)
  majorGoodMove, // Excellent move (!!)
  minorBadMove, // Dubious move (?)
  majorBadMove, // Blunder (??)
}
