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

class _MoveTimeSlider extends StatelessWidget {
  const _MoveTimeSlider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).moveTime,
      child: ValueListenableBuilder(
        valueListenable: LocalDatabaseService.listenPreferences,
        builder: (context, Box<Preferences> prefBox, _) {
          final Preferences _preferences = prefBox.get(
            LocalDatabaseService.preferencesKey,
            defaultValue: const Preferences(),
          )!;

          return Slider(
            value: LocalDatabaseService.preferences.moveTime.toDouble(),
            max: 60,
            divisions: 60,
            label: LocalDatabaseService.preferences.moveTime.toString(),
            onChanged: (value) {
              LocalDatabaseService.preferences =
                  _preferences.copyWith(moveTime: value.toInt());

              debugPrint("Move time Slider value: $value");
            },
          );
        },
      ),
    );
  }
}
