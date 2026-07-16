// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

          return _MoveTimeSliderBody(
            initialValue: generalSettings.moveTime.toDouble(),
          );
        },
      ),
    );
  }
}

class _MoveTimeSliderBody extends StatefulWidget {
  const _MoveTimeSliderBody({required this.initialValue});

  final double initialValue;

  @override
  State<_MoveTimeSliderBody> createState() => _MoveTimeSliderBodyState();
}

class _MoveTimeSliderBodyState extends State<_MoveTimeSliderBody> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(0, 60);
  }

  @override
  void didUpdateWidget(_MoveTimeSliderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the settings were changed elsewhere while the bottom sheet is open,
    // reflect the new value (we only commit to DB onChangeEnd).
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue.clamp(0, 60);
    }
  }

  void _commit(double value) {
    final int intValue = value.toInt();
    final GeneralSettings current = DB().generalSettings;
    DB().generalSettings = current.copyWith(moveTime: intValue);

    if (intValue == 0) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).noTimeLimitForThinking,
      );
    } else {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).noteAiThinkingTimeMayNotBePrecise,
      );
    }

    logger.t("Move time Slider committed value: $intValue");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('move_time_slider_center'),
      child: SizedBox(
        key: const Key('move_time_slider_sized_box'),
        width: MediaQuery.of(context).size.width * 0.8,
        child: Slider(
          key: const Key('move_time_slider_slider'),
          value: _value,
          max: 60,
          divisions: 60,
          label: _value.toInt().toString(),
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
