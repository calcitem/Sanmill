// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async' show FutureOr, Timer, unawaited;

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/models/display_settings.dart';
import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../services/diagnostic_config_snapshot.dart';

typedef EngineOptionsUpdate = FutureOr<void> Function();
typedef RecordingEventWriter =
    void Function(RecordingEventType type, Map<String, dynamic> data);
typedef SettingsDebounceTimer =
    Timer Function(Duration duration, void Function() callback);

/// Coordinates side effects that must happen after settings are persisted.
///
/// Engine-option callbacks ([updateGeneralEngineOptions],
/// [updateRuleEngineOptions]) default to no-ops so that this class carries no
/// direct dependency on any game module. The production wiring is injected by
/// the app bootstrap (see `main.dart`) after the Mill module is available.
class SettingsSideEffectCoordinator {
  SettingsSideEffectCoordinator({
    Duration engineOptionsDebounceDuration = _defaultDebounceDuration,
    EngineOptionsUpdate? updateGeneralEngineOptions,
    EngineOptionsUpdate? updateRuleEngineOptions,
    RecordingEventWriter? recordEvent,
    SettingsDebounceTimer createTimer = Timer.new,
  }) : _engineOptionsDebounceDuration = engineOptionsDebounceDuration,
       _updateGeneralEngineOptions =
           updateGeneralEngineOptions ?? _engineOptionsNoOp,
       _updateRuleEngineOptions = updateRuleEngineOptions ?? _engineOptionsNoOp,
       _recordEvent =
           recordEvent ??
           ((RecordingEventType type, Map<String, dynamic> data) {
             RecordingService().recordEvent(type, data);
           }),
       _createTimer = createTimer;

  static FutureOr<void> _engineOptionsNoOp() {}

  /// Mutable so that the app bootstrap can replace the default no-op instance
  /// with a fully-wired coordinator before any settings page is shown.
  ///
  /// Callers that need the engine to respond to settings changes must ensure
  /// the instance is configured with real callbacks (see `main.dart`).
  static SettingsSideEffectCoordinator instance =
      SettingsSideEffectCoordinator();

  static const Duration _defaultDebounceDuration = Duration(milliseconds: 300);

  final Duration _engineOptionsDebounceDuration;
  final EngineOptionsUpdate _updateGeneralEngineOptions;
  final EngineOptionsUpdate _updateRuleEngineOptions;
  final RecordingEventWriter _recordEvent;
  final SettingsDebounceTimer _createTimer;

  Timer? _engineOptionsDebounceTimer;
  Timer? _engineRuleOptionsDebounceTimer;
  final Map<String, Map<String, dynamic>> _lastSafeSettings =
      <String, Map<String, dynamic>>{};

  void onGeneralSettingsSaved(
    GeneralSettings generalSettings, {
    GeneralSettings? previous,
  }) {
    _scheduleGeneralEngineOptionsUpdate();
    _recordSettingsChange(
      'general',
      generalSettings.toJson(),
      previousSettings: previous?.toJson(),
    );
  }

  void onRuleSettingsPersisted() {
    _scheduleRuleEngineOptionsUpdate();
  }

  void recordRuleSettingsChange(
    RuleSettings ruleSettings, {
    RuleSettings? previous,
  }) {
    _recordSettingsChange(
      'rule',
      ruleSettings.toJson(),
      previousSettings: previous?.toJson(),
    );
  }

  void onDisplaySettingsSaved(
    DisplaySettings displaySettings, {
    DisplaySettings? previous,
  }) {
    _recordSettingsChange(
      'display',
      displaySettings.toJson(),
      previousSettings: previous?.toJson(),
    );
  }

  void onColorSettingsSaved(
    ColorSettings colorSettings, {
    ColorSettings? previous,
  }) {
    _recordSettingsChange(
      'color',
      colorSettings.toJson(),
      previousSettings: previous?.toJson(),
    );
  }

  void dispose() {
    _engineOptionsDebounceTimer?.cancel();
    _engineOptionsDebounceTimer = null;
    _engineRuleOptionsDebounceTimer?.cancel();
    _engineRuleOptionsDebounceTimer = null;
  }

  void _scheduleGeneralEngineOptionsUpdate() {
    _engineOptionsDebounceTimer?.cancel();
    _engineOptionsDebounceTimer = _createTimer(
      _engineOptionsDebounceDuration,
      () => _runEngineOptionsUpdate(_updateGeneralEngineOptions),
    );
  }

  void _scheduleRuleEngineOptionsUpdate() {
    _engineRuleOptionsDebounceTimer?.cancel();
    _engineRuleOptionsDebounceTimer = _createTimer(
      _engineOptionsDebounceDuration,
      () => _runEngineOptionsUpdate(_updateRuleEngineOptions),
    );
  }

  void _runEngineOptionsUpdate(EngineOptionsUpdate update) {
    unawaited(Future<void>.sync(update));
  }

  void _recordSettingsChange(
    String category,
    Map<String, dynamic> settings, {
    Map<String, dynamic>? previousSettings,
  }) {
    final Set<String> allowed = switch (category) {
      'general' => DiagnosticConfigSchema.generalReportAndApply,
      'rule' => DiagnosticConfigSchema.ruleReportAndApply,
      'display' => DiagnosticConfigSchema.displayReportAndApply,
      'color' => DiagnosticConfigSchema.colorReportAndApply,
      _ => const <String>{},
    };
    final Map<String, dynamic> safe = <String, dynamic>{
      for (final String key in allowed)
        if (settings.containsKey(key)) key: settings[key],
    };
    final Map<String, dynamic>? previous = previousSettings == null
        ? _lastSafeSettings[category]
        : <String, dynamic>{
            for (final String key in allowed)
              if (previousSettings.containsKey(key)) key: previousSettings[key],
          };
    _lastSafeSettings[category] = safe;
    if (previous == null) {
      _recordEvent(RecordingEventType.settingsChange, <String, dynamic>{
        'category': category,
        'settingId': 'initialSnapshotChanged',
      });
      return;
    }
    for (final String key in safe.keys) {
      if (previous[key] == safe[key]) {
        continue;
      }
      _recordEvent(RecordingEventType.settingsChange, <String, dynamic>{
        'category': category,
        'settingId': key,
        'oldValue': previous[key],
        'newValue': safe[key],
      });
    }
  }
}
