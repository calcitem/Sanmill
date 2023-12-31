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

import 'package:mockito/mockito.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

class MockDB extends Mock implements DB {
  GeneralSettings _generalSettings = const GeneralSettings();
  RuleSettings _ruleSettings = const RuleSettings();
  DisplaySettings _displaySettings = const DisplaySettings();
  ColorSettings _colorSettings = const ColorSettings();

  /// Gets the given [generalSettings] from the settings Box
  @override
  GeneralSettings get generalSettings => _generalSettings;

  /// Saves the given [generalSettings] to the settings Box
  @override
  set generalSettings(GeneralSettings generalSettings) =>
      _generalSettings = generalSettings;

  /// Gets the given [ruleSettings] from the settings Box
  @override
  RuleSettings get ruleSettings => _ruleSettings;

  /// Saves the given [ruleSettings] to the settings Box
  @override
  set ruleSettings(RuleSettings ruleSettings) => _ruleSettings = ruleSettings;

  /// Gets the given [displaySettings] from the settings Box
  @override
  DisplaySettings get displaySettings => _displaySettings;

  /// Saves the given [displaySettings] to the settings Box
  @override
  set displaySettings(DisplaySettings displaySettings) =>
      _displaySettings = displaySettings;

  /// Gets the given [colorSettings] from the settings Box
  @override
  ColorSettings get colorSettings => _colorSettings;

  /// Saves the given [colorSettings] to the settings Box
  @override
  set colorSettings(ColorSettings colorSettings) =>
      _colorSettings = colorSettings;
}
