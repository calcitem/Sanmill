// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// human_database_min_games_slider.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _HumanDatabaseMinGamesSlider extends StatelessWidget {
  const _HumanDatabaseMinGamesSlider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('human_database_min_games_slider_semantics'),
      label: S.of(context).humanGameDatabaseMinGames,
      child: ValueListenableBuilder<Box<GeneralSettings>>(
        key: const Key(
          'human_database_min_games_slider_value_listenable_builder',
        ),
        valueListenable: DB().listenGeneralSettings,
        builder: (BuildContext context, Box<GeneralSettings> box, _) {
          final GeneralSettings generalSettings = box.get(
            DB.generalSettingsKey,
            defaultValue: const GeneralSettings(),
          )!;

          return _HumanDatabaseMinGamesSliderBody(
            initialValue: generalSettings.humanDatabaseMinGames.toDouble(),
          );
        },
      ),
    );
  }
}

class _HumanDatabaseMinGamesSliderBody extends StatefulWidget {
  const _HumanDatabaseMinGamesSliderBody({required this.initialValue});

  final double initialValue;

  @override
  State<_HumanDatabaseMinGamesSliderBody> createState() =>
      _HumanDatabaseMinGamesSliderBodyState();
}

class _HumanDatabaseMinGamesSliderBodyState
    extends State<_HumanDatabaseMinGamesSliderBody> {
  // Slider range: 1 (consult the database for almost any sampled position) up
  // to 50 (only well-played positions, essentially opening-only). Game counts
  // grow into the thousands in the opening, so 50 already keeps the opening
  // while filtering sparse mid-game/endgame entries.
  static const double _min = 1;
  static const double _max = 50;

  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(_min, _max);
  }

  @override
  void didUpdateWidget(_HumanDatabaseMinGamesSliderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue.clamp(_min, _max);
    }
  }

  void _commit(double value) {
    final int intValue = value.toInt();
    final GeneralSettings current = DB().generalSettings;
    DB().generalSettings = current.copyWith(humanDatabaseMinGames: intValue);
    logger.t("Human database min games slider committed value: $intValue");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('human_database_min_games_slider_center'),
      child: SizedBox(
        key: const Key('human_database_min_games_slider_sized_box'),
        width: MediaQuery.of(context).size.width * 0.8,
        child: Slider(
          key: const Key('human_database_min_games_slider_slider'),
          value: _value,
          min: _min,
          max: _max,
          divisions: (_max - _min).toInt(),
          label: '${_value.toInt()}',
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
