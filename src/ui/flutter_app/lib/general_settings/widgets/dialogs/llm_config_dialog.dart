// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../../shared/models/llm_settings.dart';
import '../../../shared/services/llm_secure_store.dart';
import '../../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../models/general_settings.dart';

/// Configures the narrow, consent-gated AI game analysis feature.
class LlmConfigDialog extends StatefulWidget {
  const LlmConfigDialog({super.key});

  @override
  State<LlmConfigDialog> createState() => _LlmConfigDialogState();
}

class _LlmConfigDialogState extends State<LlmConfigDialog> {
  late LlmSettings _original;
  late LlmTransport _transport;
  late bool _enabled;
  late bool _adultConfirmed;
  late bool _remoteConsent;
  late final TextEditingController _endpointController;
  late final TextEditingController _modelController;
  late final TextEditingController _operatorController;
  late final TextEditingController _privacyController;
  late final TextEditingController _tokenController;
  bool _loadingToken = true;
  bool _saving = false;

  bool get _isDesktop {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    _original = DB().llmSettings;
    _transport = _original.transport;
    _enabled = _original.enabled;
    _adultConfirmed = _original.hasValidConsent;
    _remoteConsent =
        _original.hasValidConsent &&
        _original.transport == LlmTransport.selfHostedProxy;
    _endpointController = SafeTextEditingController(text: _original.endpoint);
    _modelController = SafeTextEditingController(text: _original.model);
    _operatorController = SafeTextEditingController(
      text: _original.proxyOperatorName,
    );
    _privacyController = SafeTextEditingController(
      text: _original.proxyPrivacyPolicyUrl,
    );
    _tokenController = SafeTextEditingController();
    for (final TextEditingController controller in <TextEditingController>[
      _endpointController,
      _modelController,
      _operatorController,
      _privacyController,
    ]) {
      controller.addListener(_invalidateConsentIfConfigurationChanged);
    }
    _loadToken();
  }

  Future<void> _loadToken() async {
    final String token = await LlmSecureStore().readProxyToken();
    if (!mounted) {
      return;
    }
    setState(() {
      _tokenController.text = token;
      _loadingToken = false;
    });
  }

  void _invalidateConsentIfConfigurationChanged() {
    final LlmSettings candidate = _candidateSettings();
    if (candidate.configurationDigest == _original.configurationDigest) {
      return;
    }
    if (_adultConfirmed || _remoteConsent) {
      setState(() {
        _adultConfirmed = false;
        _remoteConsent = false;
      });
    }
  }

  LlmSettings _candidateSettings() {
    return _original.copyWith(
      enabled: _enabled,
      transport: _transport,
      endpoint: _endpointController.text.trim(),
      model: _modelController.text.trim(),
      proxyOperatorName: _operatorController.text.trim(),
      proxyPrivacyPolicyUrl: _privacyController.text.trim(),
      migrationNoticePending: false,
    );
  }

  bool _isValidEndpoint(LlmSettings candidate) {
    final Uri? uri = Uri.tryParse(candidate.endpoint);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    if (candidate.transport == LlmTransport.selfHostedProxy) {
      return uri.scheme == 'https';
    }
    final String host = uri.host.toLowerCase();
    return _isDesktop &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  bool _isValidPrivacyUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  bool _validate(LlmSettings candidate) {
    if (candidate.endpoint.isEmpty ||
        candidate.model.isEmpty ||
        !_isValidEndpoint(candidate)) {
      return false;
    }
    if (candidate.transport == LlmTransport.selfHostedProxy &&
        (candidate.proxyOperatorName.isEmpty ||
            !_isValidPrivacyUrl(candidate.proxyPrivacyPolicyUrl))) {
      return false;
    }
    if (_enabled &&
        (!_adultConfirmed ||
            (candidate.transport == LlmTransport.selfHostedProxy &&
                !_remoteConsent))) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    final LlmSettings candidate = _candidateSettings();
    if (!_validate(candidate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).aiAnalysisInvalidConfiguration)),
      );
      return;
    }
    setState(() => _saving = true);
    final LlmSettings saved = _enabled
        ? candidate
              .copyWith(
                adultConfirmed: _adultConfirmed,
                remoteTransmissionConsented:
                    candidate.transport == LlmTransport.selfHostedProxy &&
                    _remoteConsent,
              )
              .grantConsent(enable: true)
        : candidate.revokeConsent();
    DB().llmSettings = saved;
    if (saved.transport == LlmTransport.selfHostedProxy && saved.enabled) {
      await LlmSecureStore().writeProxyToken(_tokenController.text);
    } else {
      await LlmSecureStore().clearProxyToken();
    }
    DB().generalSettings = DB().generalSettings.copyWith(
      aiChatEnabled: saved.enabled,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _revoke() async {
    setState(() => _saving = true);
    DB().llmSettings = _candidateSettings().revokeConsent();
    await LlmSecureStore().clearProxyToken();
    DB().generalSettings = DB().generalSettings.copyWith(aiChatEnabled: false);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final Uri? uri = Uri.tryParse(_privacyController.text.trim());
    if (uri != null && _isValidPrivacyUrl(uri.toString())) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _operatorController.dispose();
    _privacyController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final bool remote = _transport == LlmTransport.selfHostedProxy;
    return AlertDialog(
      title: Text(strings.aiAnalysisSettingsTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_original.migrationNoticePending)
                _NoticeCard(
                  icon: Icons.security,
                  text: strings.aiAnalysisMigrationNotice,
                ),
              _NoticeCard(
                icon: Icons.smart_toy_outlined,
                text: strings.aiAnalysisDisclosure,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.aiAnalysisEnable),
                value: _enabled,
                onChanged: _saving
                    ? null
                    : (bool value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<LlmTransport>(
                initialValue: _transport,
                decoration: InputDecoration(
                  labelText: strings.aiAnalysisTransport,
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<LlmTransport>>[
                  DropdownMenuItem<LlmTransport>(
                    value: LlmTransport.selfHostedProxy,
                    child: Text(strings.aiAnalysisSelfHostedProxy),
                  ),
                  DropdownMenuItem<LlmTransport>(
                    value: LlmTransport.localOllama,
                    enabled: _isDesktop,
                    child: Text(strings.aiAnalysisLocalOllama),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (LlmTransport? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _transport = value;
                          _adultConfirmed = false;
                          _remoteConsent = false;
                        });
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _endpointController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.aiAnalysisEndpoint,
                  hintText: remote
                      ? strings.aiAnalysisEndpointProxyHint
                      : strings.aiAnalysisEndpointLocalHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.aiAnalysisModel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (remote) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: _operatorController,
                  decoration: InputDecoration(
                    labelText: strings.aiAnalysisProxyOperator,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _privacyController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.aiAnalysisProxyPrivacyUrl,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _openPrivacyPolicy,
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  enabled: !_loadingToken,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.aiAnalysisAccessToken,
                    helperText: kIsWeb
                        ? strings.aiAnalysisAccessTokenWebHint
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                remote
                    ? strings.aiAnalysisRemoteDataSummary
                    : strings.aiAnalysisLocalDataSummary,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _adultConfirmed,
                onChanged: _enabled && !_saving
                    ? (bool? value) =>
                          setState(() => _adultConfirmed = value ?? false)
                    : null,
                title: Text(strings.aiAnalysisAgeConfirmation),
              ),
              if (remote)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _remoteConsent,
                  onChanged: _enabled && !_saving
                      ? (bool? value) =>
                            setState(() => _remoteConsent = value ?? false)
                      : null,
                  title: Text(strings.aiAnalysisRemoteConsent),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (_original.enabled || _original.hasValidConsent)
          TextButton(
            onPressed: _saving ? null : _revoke,
            child: Text(strings.aiAnalysisRevoke),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _saving || _loadingToken ? null : _save,
          child: Text(strings.aiAnalysisSaveAndConsent),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: colors.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
