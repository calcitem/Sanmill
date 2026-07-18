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
    final S strings = S.of(context);

    return SafeArea(
      key: const Key('move_time_slider_sheet'),
      minimum: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: <Widget>[
              Text(
                strings.moveTime,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                strings.aiThinkingTimeValue(_value.toInt()),
                key: const Key('move_time_slider_current_value'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            key: const Key('move_time_slider_slider'),
            value: _value,
            max: 60,
            divisions: 60,
            label: strings.aiThinkingTimeValue(_value.toInt()),
            onChanged: (double value) {
              setState(() {
                _value = value;
              });
            },
            onChangeEnd: _commit,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('move_time_slider_done'),
              onPressed: () => Navigator.pop(context),
              child: Text(strings.done),
            ),
          ),
        ],
      ),
    );
  }
}
