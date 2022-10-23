// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

import 'package:catcher/catcher.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soundpool/soundpool.dart';

import '../../generated/assets/assets.gen.dart';
import '../../generated/intl/l10n.dart';
import '../../main.dart';
import '../../models/color_settings.dart';
import '../../models/general_settings.dart';
import '../../models/rule_settings.dart';
import '../../shared/iterable/array_helper.dart';
import '../../shared/iterable/pointed_list.dart';
import '../../shared/scaffold_messenger.dart';
import '../../shared/string_buffer_helper.dart';
import '../../shared/theme/app_theme.dart';
import '../database/database.dart';
import '../environment_config.dart';
import '../logger.dart';

part 'src/audios.dart';
part 'src/board_semantics_notifier.dart';
part 'src/controller.dart';
part 'src/engine.dart';
part 'src/ext_move.dart';
part 'src/game.dart';
part 'src/game_result_notifier.dart';
part 'src/header_icons_notifier.dart';
part 'src/history_navigation.dart';
part 'src/import_export_service.dart';
part 'src/mills.dart';
part 'src/position.dart';
part 'src/recorder.dart';
part 'src/responses.dart';
part 'src/save_load_service.dart';
part 'src/setup_position_notifier.dart';
part 'src/tap_handler.dart';
part 'src/tip_notifier.dart';
part 'src/types.dart';
part 'src/zobrist.dart';

// TODO: [Leptopoda] Separate the ui from the logic
