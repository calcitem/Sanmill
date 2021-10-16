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

part of 'package:sanmill/screens/game_settings/game_settings_page.dart';

class _SkillLevelSlider extends StatelessWidget {
  const _SkillLevelSlider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).skillLevel,
        child: ValueListenableBuilder(
          valueListenable: LocalDatabaseService.listenPreferences,
          builder: (context, Box<Preferences> prefBox, _) {
            final Preferences _preferences = prefBox.get(
              LocalDatabaseService.preferencesKey,
              defaultValue: const Preferences(),
            )!;

            return Slider(
              value: _preferences.skillLevel.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: _preferences.skillLevel.toString(),
              onChanged: (value) {
                LocalDatabaseService.preferences = _preferences.copyWith(skillLevel: value.toInt());
                debugPrint("Skill level Slider value: $value");
              },
            );
          },
        ),
      ),
    );
  }
}
