// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/online_play/online_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  final OnlineServiceConfig service = OnlineServiceConfig(
    Uri.parse('https://online.example'),
  );
  final String roomId = List<String>.filled(22, 'R').join();
  final String token = List<String>.filled(43, 'T').join();

  test('validates HTTPS and app-scheme invitation links locally', () {
    expect(
      OnlineInvite.tryParse(
        'https://online.example/invite/$roomId#$token',
        service,
      ),
      isNotNull,
    );
    expect(
      OnlineInvite.tryParse('sanmill://invite/$roomId#$token', service),
      isNotNull,
    );
    expect(
      OnlineInvite.tryParse(
        'https://attacker.example/invite/$roomId#$token',
        service,
      ),
      isNull,
    );
    expect(
      OnlineInvite.tryParse(
        'https://online.example/invite/$roomId?token=$token',
        service,
      ),
      isNull,
    );
  });

  test('Mill rule options round-trip between Flutter and Worker schema', () {
    const RuleSettings source = RuleSettings(
      piecesCount: 12,
      hasDiagonalLines: true,
      mayFly: false,
      mayRemoveMultiple: true,
      enableCustodianCapture: true,
      boardFullAction: BoardFullAction.agreeToDraw,
      stalemateAction: StalemateAction.endWithStalemateDraw,
    );
    final Map<String, Object?> options = onlineOptionsFromRuleSettings(source);
    final RuleSettings restored = ruleSettingsFromOnlineOptions(options);

    expect(restored.piecesCount, source.piecesCount);
    expect(restored.hasDiagonalLines, isTrue);
    expect(restored.mayFly, isFalse);
    expect(restored.mayRemoveMultiple, isTrue);
    expect(restored.enableCustodianCapture, isTrue);
    expect(restored.boardFullAction, BoardFullAction.agreeToDraw);
    expect(restored.stalemateAction, StalemateAction.endWithStalemateDraw);
  });
}
