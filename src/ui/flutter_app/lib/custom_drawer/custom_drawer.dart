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

library;

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

import '../generated/intl/l10n.dart';
import '../shared/config/constants.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_theme.dart';
import '../shared/utils/helpers/text_helpers/text_size_helper.dart';

part 'widgets/custom_drawer_controller.dart';
part 'widgets/custom_drawer_header.dart';
part 'widgets/custom_drawer_icon.dart';
part 'widgets/custom_drawer_item.dart';
part 'widgets/custom_drawer_value.dart';
part 'widgets/custom_drawer_widget.dart';
