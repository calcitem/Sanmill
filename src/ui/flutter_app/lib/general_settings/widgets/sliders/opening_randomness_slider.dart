// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// opening_randomness_slider.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _OpeningRandomnessSlider extends StatelessWidget {
  const _OpeningRandomnessSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('opening_randomness_slider_semantics'),
      label: S.of(context).openingRandomness,
      child: ValueListenableBuilder<Box<GeneralSettings>>(
        key: const Key('opening_randomness_slider_value_listenable_builder'),
        valueListenable: DB().listenGeneralSettings,
        builder: (BuildContext context, Box<GeneralSettings> box, _) {
          final GeneralSettings generalSettings = box.get(
            DB.generalSettingsKey,
            defaultValue: const GeneralSettings(),
          )!;

          return _OpeningRandomnessSliderBody(
            initialValue: generalSettings.openingRandomness.toDouble(),
          );
        },
      ),
    );
  }
}

class _OpeningRandomnessSliderBody extends StatefulWidget {
  const _OpeningRandomnessSliderBody({required this.initialValue});

  final double initialValue;

  @override
  State<_OpeningRandomnessSliderBody> createState() =>
      _OpeningRandomnessSliderBodyState();
}

class _OpeningRandomnessSliderBodyState
    extends State<_OpeningRandomnessSliderBody> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(0, 100);
  }

  @override
  void didUpdateWidget(_OpeningRandomnessSliderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue.clamp(0, 100);
    }
  }

  void _commit(double value) {
    final int intValue = value.toInt();
    final GeneralSettings current = DB().generalSettings;
    DB().generalSettings = current.copyWith(openingRandomness: intValue);
    logger.t("Opening randomness slider committed value: $intValue");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('opening_randomness_slider_center'),
      child: SizedBox(
        key: const Key('opening_randomness_slider_sized_box'),
        width: MediaQuery.of(context).size.width * 0.8,
        child: Slider(
          key: const Key('opening_randomness_slider_slider'),
          value: _value,
          max: 100,
          divisions: 20,
          label: '${_value.toInt()}%',
          onChanged: (double value) {
            setState(() {
              _value = value;
            });
          },
          onChangeEnd: _commit,
        ),
      ),
    );
  }
}
