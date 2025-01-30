// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule_set_modal.dart

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

// A modal widget to select a rule set for the game.
class _RuleSetModal extends StatelessWidget {
  const _RuleSetModal({
    required this.ruleSet,
    required this.onChanged,
  });

  final RuleSet ruleSet;
  final Function(RuleSet?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('rule_set_semantics'),
      label: S.of(context).ruleSet,
      child: SingleChildScrollView(
        key: const Key('rule_set_scroll_view'),
        child: Column(
          key: const Key('rule_set_column'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile<RuleSet>(
              key: const Key('radio_current_rule'),
              title: Text(S.of(context).currentRule),
              groupValue: ruleSet,
              value: RuleSet.current,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_nine_mens_morris'),
              title: Text(S.of(context).nineMensMorris),
              groupValue: ruleSet,
              value: RuleSet.nineMensMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_twelve_mens_morris'),
              title: Text(S.of(context).twelveMensMorris),
              groupValue: ruleSet,
              value: RuleSet.twelveMensMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_morabaraba'),
              title: Text(S.of(context).morabaraba),
              groupValue: ruleSet,
              value: RuleSet.morabaraba,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_dooz'),
              title: Text(S.of(context).dooz),
              groupValue: ruleSet,
              value: RuleSet.dooz,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_lasker_morris'),
              title: Text(S.of(context).laskerMorris),
              groupValue: ruleSet,
              value: RuleSet.laskerMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_one_time_mill'),
              title: Text(S.of(context).oneTimeMill),
              groupValue: ruleSet,
              value: RuleSet.oneTimeMill,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_cham_gonu'),
              title: Text(S.of(context).chamGonu),
              groupValue: ruleSet,
              value: RuleSet.chamGonu,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_zhi_qi'),
              title: Text(S.of(context).zhiQi),
              groupValue: ruleSet,
              value: RuleSet.zhiQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_cheng_san_qi'),
              title: Text(S.of(context).chengSanQi),
              groupValue: ruleSet,
              value: RuleSet.chengSanQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_da_san_qi'),
              title: Text(S.of(context).daSanQi),
              groupValue: ruleSet,
              value: RuleSet.daSanQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_mul_mulan'),
              title: Text(S.of(context).mulMulan),
              groupValue: ruleSet,
              value: RuleSet.mulMulan,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_nerenchi'),
              title: Text(S.of(context).nerenchi),
              groupValue: ruleSet,
              value: RuleSet.nerenchi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              key: const Key('radio_elfilja'),
              title: Text(S.of(context).elfilja),
              groupValue: ruleSet,
              value: RuleSet.elfilja,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
