// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// font_size_slider.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _FontSizeSlider extends StatelessWidget {
  const _FontSizeSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DisplaySettings>>(
      key: const Key('font_size_slider_value_listenable_builder'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        final DisplaySettings displaySettings = box.get(
          DB.displaySettingsKey,
          defaultValue: const DisplaySettings(),
        )!;
        final String valueLabel =
            '${displaySettings.fontScale.toStringAsFixed(2)}×';

        return _SettingsSliderSheet(
          keyPrefix: 'font_size_slider',
          title: S.of(context).fontSize,
          valueLabel: valueLabel,
          slider: Slider(
            key: const Key('font_size_slider_slider'),
            value: displaySettings.fontScale,
            min: 1,
            max: 2,
            divisions: 16,
            label: valueLabel,
            semanticFormatterCallback: (double value) =>
                '${value.toStringAsFixed(2)}×',
            onChanged: (double value) {
              logger.t("[config] fontSize value: $value");
              DB().displaySettings = displaySettings.copyWith(fontScale: value);
            },
          ),
          preview: Text(
            S.of(context).fontSizePreview,
            key: const Key('font_size_slider_text'),
          ),
        );
      },
    );
  }
}
