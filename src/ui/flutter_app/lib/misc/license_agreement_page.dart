// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// license_agreement_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../generated/assets/assets.gen.dart';
import '../generated/intl/l10n.dart';

class LicenseAgreementPage extends StatelessWidget {
  const LicenseAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return FutureBuilder<String>(
      future: rootBundle.loadString(Assets.licenses.gpl30),
      builder: (BuildContext context, AsyncSnapshot<String> data) {
        late final String str;
        if (!data.hasData) {
          str = S.of(context).nothingToShow;
        } else {
          str = data.data!;
        }

        return BlockSemantics(
          child: Scaffold(
            key: const Key('license_agreement_page_scaffold'),
            resizeToAvoidBottomInset: false,
            backgroundColor: theme.colorScheme.surface,
            appBar: AppBar(
              key: const Key('license_agreement_page_appbar'),
              title: Text(
                S.of(context).license,
                key: const Key('license_agreement_page_appbar_title'),
              ),
            ),
            body: SingleChildScrollView(
              key: const Key('license_agreement_page_scrollview'),
              padding: const EdgeInsets.all(16),
              child: Text(
                str,
                key: const Key('license_agreement_page_body_text'),
                style: theme.textTheme.bodySmall!.copyWith(
                  fontFamily: "Monospace",
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        );
      },
    );
  }
}
