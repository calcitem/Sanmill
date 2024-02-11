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
library painters;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../appearance_settings/models/color_settings.dart';
import '../../../appearance_settings/models/display_settings.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/environment_config.dart';
import '../../../shared/themes/app_theme.dart';
import '../../services/mill.dart';

part 'board_painter.dart';
part 'board_utils.dart';
part 'piece_painter.dart';
