// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// license_agreement_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../appearance_settings/models/color_settings.dart';
import '../generated/assets/assets.gen.dart';
import '../generated/intl/l10n.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_theme.dart';

class LicenseAgreementPage extends StatelessWidget {
  const LicenseAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);

        return FutureBuilder<String>(
          future: rootBundle.loadString(Assets.licenses.gpl30),
          builder: (BuildContext context, AsyncSnapshot<String> data) {
            late final String str;
            if (!data.hasData) {
              str = S.of(context).nothingToShow;
            } else {
              str = data.data!;
            }

            final Widget page = BlockSemantics(
              child: Scaffold(
                key: const Key('license_agreement_page_scaffold'),
                resizeToAvoidBottomInset: false,
                backgroundColor: useDarkSettingsUi
                    ? settingsTheme.scaffoldBackgroundColor
                    : null,
                appBar: AppBar(
                  key: const Key('license_agreement_page_appbar'),
                  title: Text(
                    S.of(context).license,
                    style: useDarkSettingsUi
                        ? null
                        : AppTheme.appBarTheme.titleTextStyle,
                    key: const Key('license_agreement_page_appbar_title'),
                  ),
                ),
                body: SingleChildScrollView(
                  key: const Key('license_agreement_page_scrollview'),
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    str,
                    key: const Key('license_agreement_page_body_text'),
                    style: settingsTheme.textTheme.bodySmall!.copyWith(
                      fontFamily: "Monospace",
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            );

            return useDarkSettingsUi
                ? Theme(data: settingsTheme, child: page)
                : page;
          },
        );
      },
    );
  }
}
