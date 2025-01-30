// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// privacy_policy_dialog.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../general_settings/models/general_settings.dart';
import '../../generated/intl/l10n.dart';
import '../config/constants.dart';
import '../database/database.dart';
import '../services/logger.dart';
import '../widgets/link_text_span.dart';

class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key, this.onConfirm});

  final VoidCallback? onConfirm;

  void _acceptPrivacyPolicy() {
    _setPrivacyPolicyAcceptance(value: true);
    logger.i("[config] isPrivacyPolicyAccepted: true");
  }

  static Future<void> _setPrivacyPolicyAcceptance({required bool value}) async {
    DB().generalSettings =
        DB().generalSettings.copyWith(isPrivacyPolicyAccepted: value);

    logger.t("[config] isPrivacyPolicyAccepted: $value");
  }

  static RichText _buildPrivacyPolicyText(
      BuildContext context, TextStyle bodyTextStyle, TextStyle linkTextStyle) {
    final String eulaURL = !kIsWeb && (Platform.isIOS || Platform.isMacOS)
        ? Constants.appleStandardEulaUrl
        : Constants.endUserLicenseAgreementUrl.baseChinese;
    final String privacyPolicyURL = Constants.privacyPolicyUrl.baseChinese;

    return RichText(
      text: TextSpan(
        children: <TextSpan>[
          TextSpan(
            style: bodyTextStyle,
            text: S.of(context).privacyPolicy_Detail_1,
          ),
          LinkTextSpan(
            style: linkTextStyle,
            text: S.of(context).eula,
            url: eulaURL,
          ),
          TextSpan(
            style: bodyTextStyle,
            text: S.of(context).and,
          ),
          LinkTextSpan(
            style: linkTextStyle,
            text: S.of(context).privacyPolicy,
            url: privacyPolicyURL,
          ),
          TextSpan(
            style: bodyTextStyle,
            text: S.of(context).privacyPolicy_Detail_2,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      Localizations.localeOf(context).languageCode.startsWith("zh"),
      "The current locale must start with 'zh'",
    );

    final ThemeData currentTheme = Theme.of(context);
    final TextStyle bodyLargeTextStyle = currentTheme.textTheme.bodyLarge!;
    final TextStyle linkTextStyle =
        bodyLargeTextStyle.copyWith(color: currentTheme.colorScheme.secondary);

    return AlertDialog(
      title: Text(
        S.of(context).privacyPolicy,
        key: const Key('privacy_policy_dialog_title'),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child:
            _buildPrivacyPolicyText(context, bodyLargeTextStyle, linkTextStyle),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('privacy_policy_accept_button'),
          child: Text(S.of(context).accept),
          onPressed: () {
            _acceptPrivacyPolicy();
            Navigator.pop(context);
            onConfirm?.call();
          },
        ),
        if (!kIsWeb && Platform.isAndroid)
          TextButton(
            key: const Key('privacy_policy_exit_button'),
            child: Text(S.of(context).exit),
            onPressed: () {
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
          ),
      ],
    );
  }
}

Future<void> showPrivacyDialog(BuildContext context) async {
  assert(Localizations.localeOf(context).languageCode.startsWith("zh_"));

  final ThemeData themeData = Theme.of(context);
  final TextStyle aboutTextStyle = themeData.textTheme.bodyLarge!;
  final TextStyle linkStyle =
      aboutTextStyle.copyWith(color: themeData.colorScheme.secondary);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AlertDialog(
      title: Text(
        S.of(context).privacyPolicy,
        key: const Key('show_privacy_dialog_title'),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: PrivacyPolicyDialog._buildPrivacyPolicyText(
            context, aboutTextStyle, linkStyle),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('show_privacy_accept_button'),
          child: Text(S.of(context).accept),
          onPressed: () {
            PrivacyPolicyDialog._setPrivacyPolicyAcceptance(value: true);
            Navigator.pop(context);
          },
        ),
        if (!kIsWeb && Platform.isAndroid)
          TextButton(
            key: const Key('show_privacy_exit_button'),
            child: Text(S.of(context).exit),
            onPressed: () {
              PrivacyPolicyDialog._setPrivacyPolicyAcceptance(value: false);
              SystemChannels.platform.invokeMethod("SystemNavigator.pop");
            },
          ),
      ],
    ),
  );
}
