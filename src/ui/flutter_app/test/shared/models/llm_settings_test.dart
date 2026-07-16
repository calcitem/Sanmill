// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/models/llm_settings.dart';

void main() {
  group('LlmSettings consent', () {
    test('requires explicit remote consent bound to the configuration', () {
      const LlmSettings initial = LlmSettings(
        enabled: true,
        endpoint: 'https://proxy.example',
        model: 'model',
        proxyOperatorName: 'Example operator',
        proxyPrivacyPolicyUrl: 'https://proxy.example/privacy',
        adultConfirmed: true,
        remoteTransmissionConsented: true,
      );

      expect(initial.hasValidConsent, isFalse);
      final LlmSettings consented = initial.grantConsent(enable: true);
      expect(consented.hasValidConsent, isTrue);
      expect(
        consented.copyWith(model: 'different-model').hasValidConsent,
        isFalse,
      );
    });

    test('revocation disables analysis and removes consent fields', () {
      const LlmSettings initial = LlmSettings(
        enabled: true,
        endpoint: 'http://localhost:11434',
        model: 'model',
        transport: LlmTransport.localOllama,
        adultConfirmed: true,
      );
      final LlmSettings revoked = initial
          .grantConsent(enable: true)
          .revokeConsent();

      expect(revoked.enabled, isFalse);
      expect(revoked.hasValidConsent, isFalse);
      expect(revoked.consentedAtEpochMs, isNull);
    });

    test('round trips only non-secret settings', () {
      const LlmSettings initial = LlmSettings(
        endpoint: 'https://proxy.example',
        model: 'model',
        proxyOperatorName: 'Example operator',
        proxyPrivacyPolicyUrl: 'https://proxy.example/privacy',
      );

      final LlmSettings restored = LlmSettings.fromJson(initial.toJson());
      expect(restored.endpoint, initial.endpoint);
      expect(restored.model, initial.model);
      expect(initial.toJson().containsKey('token'), isFalse);
      expect(initial.toJson().containsKey('apiKey'), isFalse);
    });
  });
}
