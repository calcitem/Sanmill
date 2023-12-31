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

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _MoveTimeSlider extends StatelessWidget {
  const _MoveTimeSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).moveTime,
      child: ValueListenableBuilder<Box<GeneralSettings>>(
        valueListenable: DB().listenGeneralSettings,
        builder: (BuildContext context, Box<GeneralSettings> box, _) {
          final GeneralSettings generalSettings = box.get(
            DB.generalSettingsKey,
            defaultValue: const GeneralSettings(),
          )!;

          return Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                value: DB().generalSettings.moveTime.toDouble(),
                max: 60,
                divisions: 60,
                label: DB().generalSettings.moveTime.toString(),
                onChanged: (double value) {
                  DB().generalSettings =
                      generalSettings.copyWith(moveTime: value.toInt());

                  if (DB().generalSettings.moveTime == 0) {
                    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                        S.of(context).noTimeLimitForThinking);
                  } else {
                    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                        S.of(context).noteAiThinkingTimeMayNotBePrecise);
                  }

                  logger.v("Move time Slider value: $value");
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
