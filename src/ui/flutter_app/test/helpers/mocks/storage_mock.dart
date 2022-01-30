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
import 'package:sanmill/models/general_settings.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/storage/storage.dart';

class MockedDB extends Mock implements DB {
  ColorSettings _colorSettings = const ColorSettings();
  Display _display = const Display();
  GeneralSettings _generalSettings = const GeneralSettings();
  Rules _rules = const Rules();

  /// gets the given [ColorSettings] from the settings Box
  @override
  ColorSettings get colorSettings => _colorSettings;

  /// saves the given [colors] to the settings Box
  @override
  set colorSettings(ColorSettings colors) => _colorSettings = colors;

  /// gets the given [Display] from the settings Box
  @override
  Display get display => _display;

  /// saves the given [display] to the settings Box
  @override
  set display(Display display) => _display = display;

  /// gets the given [GeneralSettings] from the settings Box
  @override
  GeneralSettings get generalSettings => _generalSettings;

  /// saves the given [settings] to the settings Box
  @override
  set generalSettings(GeneralSettings settings) => _generalSettings = settings;

  /// gets the given [Rules] from the settings Box
  @override
  Rules get rules => _rules;

  /// saves the given [rules] to the settings Box
  @override
  set rules(Rules rules) => _rules = rules;
}
