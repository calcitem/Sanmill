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
library game_toolbar;

import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/utils/helpers/string_helpers/string_buffer_helper.dart';
import '../../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../services/mill.dart';

part 'src/game_page_toolbar.dart';
part 'src/item_theme.dart';
part 'src/item_theme_data.dart';
part 'src/setup_position_toolbar.dart';
part 'src/toolbar_item.dart';
