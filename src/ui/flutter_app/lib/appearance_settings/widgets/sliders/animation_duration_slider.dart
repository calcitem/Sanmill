// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// animation_duration_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _AnimationDurationSlider extends StatelessWidget {
  const _AnimationDurationSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('animation_duration_semantics'),
      label: S.of(context).animationDuration,
      child: ValueListenableBuilder<Box<DisplaySettings>>(
        key: const Key('animation_duration_value_listenable_builder'),
        valueListenable: DB().listenDisplaySettings,
        builder: (BuildContext context, Box<DisplaySettings> box, _) {
          final DisplaySettings displaySettings = box.get(
            DB.displaySettingsKey,
            defaultValue: const DisplaySettings(),
          )!;

          return Center(
            key: const Key('animation_duration_center'),
            child: SizedBox(
              key: const Key('animation_duration_sized_box'),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Slider(
                key: const Key('animation_duration_slider'),
                value: displaySettings.animationDuration,
                max: 5.0,
                divisions: 50,
                label: displaySettings.animationDuration.toStringAsFixed(1),
                onChanged: (double value) {
                  logger.t("[config] AnimationDuration value: $value");
                  DB().displaySettings =
                      displaySettings.copyWith(animationDuration: value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
