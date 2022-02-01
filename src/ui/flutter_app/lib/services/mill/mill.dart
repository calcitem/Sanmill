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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/assets/assets.gen.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/iterable/array_helper.dart';
import 'package:sanmill/shared/iterable/pointed_list.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';
import 'package:sanmill/shared/string_buffer_helper.dart';
import 'package:soundpool/soundpool.dart';

part 'src/audios.dart';
part 'src/controller.dart';
part 'src/engine.dart';
part 'src/ext_move.dart';
part 'src/game.dart';
part 'src/history_navigation.dart';
part 'src/import_export_service.dart';
part 'src/mills.dart';
part 'src/position.dart';
part 'src/recorder.dart';
part 'src/responses.dart';
part 'src/tap_handler.dart';
part 'src/tip_state.dart';
part 'src/types.dart';
part 'src/zobrist.dart';

// TODO: [Leptopoda] Separate the ui from the logic
