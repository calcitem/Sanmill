// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// move_time_slider.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _MoveTimeSlider extends StatelessWidget {
  const _MoveTimeSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('move_time_slider_semantics'),
      label: S.of(context).moveTime,
      child: ValueListenableBuilder<Box<GeneralSettings>>(
        key: const Key('move_time_slider_value_listenable_builder'),
        valueListenable: DB().listenGeneralSettings,
        builder: (BuildContext context, Box<GeneralSettings> box, _) {
          final GeneralSettings generalSettings = box.get(
            DB.generalSettingsKey,
            defaultValue: const GeneralSettings(),
          )!;

          return Center(
            key: const Key('move_time_slider_center'),
            child: SizedBox(
              key: const Key('move_time_slider_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('move_time_slider_slider'),
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

                  logger.t("Move time Slider value: $value");
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
