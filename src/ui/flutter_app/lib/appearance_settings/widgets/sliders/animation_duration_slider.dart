// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// animation_duration_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _AnimationDurationSlider extends StatelessWidget {
  const _AnimationDurationSlider();

  @override
  Widget build(BuildContext context) {
    String formatDuration(double seconds) {
      final num roundedSeconds = num.parse(seconds.toStringAsFixed(1));
      return S.of(context).animationDurationValue(roundedSeconds);
    }

    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('animation_duration_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel = formatDuration(
          displaySettings.animationDuration,
        );

        return _SettingsSliderSheet(
          keyPrefix: 'animation_duration',
          title: S.of(context).animationDuration,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('animation_duration_slider'),
            value: displaySettings.animationDuration,
            max: 5.0,
            divisions: 50,
            label: valueLabel,
            semanticFormatterCallback: formatDuration,
            onChanged: (double value) {
              logger.t("[config] AnimationDuration value: $value");
              DB().displaySettings = displaySettings.copyWith(
                animationDuration: value,
              );
            },
          ),
        );
      },
    );
  }
}
