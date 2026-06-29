// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// settings_sub_page.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

const Duration _settingsMotionDuration = Duration(milliseconds: 220);
const Duration _settingsPageTransitionDuration = Duration(milliseconds: 260);

PageRoute<T> _settingsDrillInRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: _settingsPageTransitionDuration,
  reverseTransitionDuration: const Duration(milliseconds: 210),
  transitionsBuilder:
      (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        if (MediaQuery.of(context).disableAnimations) {
          return child;
        }

        final bool rtl = Directionality.of(context) == TextDirection.rtl;
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final Tween<Offset> offset = Tween<Offset>(
          begin: Offset(rtl ? -0.08 : 0.08, 0),
          end: Offset.zero,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: offset.animate(curved),
            child: child,
          ),
        );
      },
);

String _settingsFirstLine(String text) {
  final int newline = text.indexOf('\n');
  return newline == -1 ? text : text.substring(0, newline);
}

bool _openingBookSettingsAvailable() =>
    DB().ruleSettings.isLikelyNineMensMorris() ||
    DB().ruleSettings.isLikelyElFilja();

bool _humanDatabaseSettingsAvailable() =>
    DB().ruleSettings.isLikelyNineMensMorris();

int _aiKnowledgeSourcesAvailableCount() {
  int count = 0;
  if (_openingBookSettingsAvailable()) {
    count++;
  }
  if (!kIsWeb) {
    count++;
  }
  if (_humanDatabaseSettingsAvailable()) {
    count++;
  }
  return count;
}

int _aiKnowledgeSourcesEnabledCount(GeneralSettings settings) {
  int count = 0;
  if (_openingBookSettingsAvailable() && settings.useOpeningBook) {
    count++;
  }
  if (!kIsWeb && settings.usePerfectDatabase) {
    count++;
  }
  if (_humanDatabaseSettingsAvailable() && settings.humanDatabaseEnabled) {
    count++;
  }
  return count;
}

String _aiKnowledgeSourcesSummary(
  BuildContext context,
  GeneralSettings settings,
) {
  final int available = _aiKnowledgeSourcesAvailableCount();
  if (available == 0) {
    return S.of(context).none;
  }

  return '${_aiKnowledgeSourcesEnabledCount(settings)}/$available';
}

String _advancedAiSearchSummary(GeneralSettings settings) =>
    settings.searchAlgorithm!.name;

class _AnimatedSettingsCard extends StatelessWidget {
  const _AnimatedSettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: _settingsMotionDuration,
    curve: Curves.easeInOutCubic,
    alignment: Alignment.topCenter,
    child: child,
  );
}

class _SettingsSubPageScaffold extends StatelessWidget {
  const _SettingsSubPageScaffold({
    required this.titleBuilder,
    required this.settingsBuilder,
    required this.pageKey,
  });

  final String Function(S strings) titleBuilder;
  final Widget Function(
    BuildContext context,
    Box<GeneralSettings> box,
    Widget? child,
  )
  settingsBuilder;
  final Key pageKey;

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      key: pageKey,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: Text(titleBuilder(S.of(context)))),
        body: ValueListenableBuilder<Box<GeneralSettings>>(
          valueListenable: DB().listenGeneralSettings,
          builder: settingsBuilder,
        ),
      ),
    );
  }
}
