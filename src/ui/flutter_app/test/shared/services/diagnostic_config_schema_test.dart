// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/services/diagnostic_config_snapshot.dart';

void main() {
  test('every general setting has an explicit diagnostic classification', () {
    expect(
      DiagnosticConfigSchema.classifiedGeneralKeys,
      const GeneralSettings().toJson().keys.toSet(),
    );
  });

  test('every display setting has an explicit diagnostic classification', () {
    expect(
      DiagnosticConfigSchema.classifiedDisplayKeys,
      const DisplaySettings().toJson().keys.toSet(),
    );
  });

  test('every rule setting is explicitly reportable and applicable', () {
    expect(
      DiagnosticConfigSchema.ruleReportAndApply,
      const RuleSettings().toJson().keys.toSet(),
    );
  });

  test('every color setting has an explicit diagnostic classification', () {
    expect(
      DiagnosticConfigSchema.classifiedColorKeys,
      const ColorSettings().toJson().keys.toSet(),
    );
  });

  test('sensitive general fields cannot be applied', () {
    expect(
      DiagnosticConfigSchema.generalReportAndApply,
      isNot(contains('LlmApiKey')),
    );
    expect(
      DiagnosticConfigSchema.generalReportAndApply,
      isNot(contains('LlmBaseUrl')),
    );
    expect(
      DiagnosticConfigSchema.generalReportAndApply,
      isNot(contains('ExperienceRecordingEnabled')),
    );
    expect(
      DiagnosticConfigSchema.generalReportAndApply,
      isNot(contains('DiagnosticActionTrailEnabled')),
    );
  });

  test('untrusted unsafe config fields are rejected', () {
    expect(
      () => DiagnosticConfigSnapshot.validate(const <String, dynamic>{
        'generalSettings': <String, dynamic>{'LlmApiKey': 'secret'},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('untrusted reproducible values are range checked', () {
    expect(
      () => DiagnosticConfigSnapshot.validate(const <String, dynamic>{
        'generalSettings': <String, dynamic>{'EngineThreads': 1000000},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => DiagnosticConfigSnapshot.validate(const <String, dynamic>{
        'ruleSettings': <String, dynamic>{'PiecesCount': -1},
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
