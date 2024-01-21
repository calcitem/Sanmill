// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

/// Although marked as a library this package is tightly integrated into the app
library mill;

import 'dart:async';
import 'dart:io';

import 'package:catcher/model/catcher_options.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soundpool/soundpool.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../generated/assets/assets.gen.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/utils/helpers/array_helpers/array_helper.dart';
import '../../shared/utils/helpers/list_helpers/pointed_list.dart';
import '../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import "gif_share/gif_share.dart";

part 'controller/game_controller.dart';
part 'controller/game_recorder.dart';
part 'controller/game_responses.dart';
part 'controller/history_navigation.dart';
part 'controller/tap_handler.dart';
part 'engine/engine.dart';
part 'engine/ext_move.dart';
part 'engine/game.dart';
part 'engine/mills.dart';
part 'engine/position.dart';
part 'engine/types.dart';
part 'engine/zobrist.dart';
part 'import_export/import_export_service.dart';
part 'notifiers/board_semantics_notifier.dart';
part 'notifiers/game_result_notifier.dart';
part 'notifiers/header_icons_notifier.dart';
part 'notifiers/header_tip_notifier.dart';
part 'notifiers/setup_position_notifier.dart';
part 'save_load/save_load_service.dart';
part 'sounds/sound_manager.dart';

// TODO: [Leptopoda] Separate the ui from the logic
