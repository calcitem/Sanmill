// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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
import '../../shared/gif_share/gif_share.dart';
import '../../shared/iterable/array_helper.dart';
import '../../shared/iterable/pointed_list.dart';
import '../../shared/scaffold_messenger.dart';
import '../../shared/string_buffer_helper.dart';
import '../../shared/theme/app_theme.dart';
import '../database/database.dart';
import '../environment_config/environment_config.dart';
import '../logger/logger.dart';

part 'providers/audios.dart';
part 'providers/board_semantics_notifier.dart';
part 'providers/controller.dart';
part 'providers/engine.dart';
part 'providers/ext_move.dart';
part 'providers/game.dart';
part 'providers/game_result_notifier.dart';
part 'providers/header_icons_notifier.dart';
part 'providers/history_navigation.dart';
part 'providers/import_export_service.dart';
part 'providers/mills.dart';
part 'providers/position.dart';
part 'providers/recorder.dart';
part 'providers/responses.dart';
part 'providers/save_load_service.dart';
part 'providers/setup_position_notifier.dart';
part 'providers/tap_handler.dart';
part 'providers/tip_notifier.dart';
part 'providers/types.dart';
part 'providers/zobrist.dart';

// TODO: [Leptopoda] Separate the ui from the logic
