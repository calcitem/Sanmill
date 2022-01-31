// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/general_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class _LinkTextSpan extends TextSpan {
  _LinkTextSpan({TextStyle? style, required String url, String? text})
      : super(
          style: style,
          text: text ?? url,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (!EnvironmentConfig.test) {
                launch(url, forceSafariVC: false);
              }
            },
        );
}

Future<void> showPrivacyDialog(BuildContext context) async {
  assert(Localizations.localeOf(context).languageCode.startsWith("zh_"));

  final ThemeData themeData = Theme.of(context);
  final TextStyle aboutTextStyle = themeData.textTheme.bodyText1!;
  final TextStyle linkStyle =
      aboutTextStyle.copyWith(color: themeData.colorScheme.secondary);

  final String eulaURL = Constants.eulaURL.urlZh;
  final String privacyPolicyURL = Constants.privacyPolicyURL.urlZh;

  Future<void> _setPrivacyPolicyAccepted({required bool value}) async {
    DB().generalSettings =
        DB().generalSettings.copyWith(isPrivacyPolicyAccepted: value);

    logger.v("[config] isPrivacyPolicyAccepted: $value");
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(S.of(context).privacyPolicy),
      content: RichText(
        text: TextSpan(
          children: <TextSpan>[
            TextSpan(
              style: aboutTextStyle,
              text: S.of(context).privacyPolicy_Detail_1,
            ),
            _LinkTextSpan(
              style: linkStyle,
              text: S.of(context).eula,
              url: eulaURL,
            ),
            TextSpan(
              style: aboutTextStyle,
              text: S.of(context).and,
            ),
            _LinkTextSpan(
              style: linkStyle,
              text: S.of(context).privacyPolicy,
              url: privacyPolicyURL,
            ),
            TextSpan(
              style: aboutTextStyle,
              text: S.of(context).privacyPolicy_Detail_2,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).accept),
          onPressed: () {
            _setPrivacyPolicyAccepted(value: true);
            Navigator.pop(context);
          },
        ),
        if (Platform.isAndroid)
          TextButton(
            child: Text(S.of(context).exit),
            onPressed: () {
              _setPrivacyPolicyAccepted(value: false);
              SystemChannels.platform.invokeMethod("SystemNavigator.pop");
            },
          ),
      ],
    ),
  );
}
