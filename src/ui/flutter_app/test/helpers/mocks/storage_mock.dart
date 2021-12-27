/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:mockito/mockito.dart';
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/storage/storage.dart';


class MockedDB extends Mock implements DB {
  /// gets the given [ColorSettings] from the settings Box
  @override
  ColorSettings get colorSettings => const ColorSettings();

  /// gets the given [Display] from the settings Box
  @override
  Display get display => const Display();

  /// gets the given [Preferences] from the settings Box
  @override
  Preferences get preferences => const Preferences();

  /// gets the given [Rules] from the settings Box
  @override
  Rules get rules => Rules();
}
