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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../generated/intl/l10n.dart';
import '../models/general_settings.dart';
import '../services/database/database.dart';
import '../services/logger.dart';
import 'constants.dart';
import 'link_text_span.dart';

class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  void _setPrivacyPolicyAccepted() {
    DB().generalSettings =
        DB().generalSettings.copyWith(isPrivacyPolicyAccepted: true);

    logger.i("[config] isPrivacyPolicyAccepted: true");
  }

  @override
  Widget build(BuildContext context) {
    assert(
      Localizations.localeOf(context).languageCode.startsWith("zh"),
      "The current locale must start with 'zh'",
    );
    assert(
      !DB().generalSettings.isPrivacyPolicyAccepted,
      "The privacy policy must not be accepted",
    );

    final ThemeData themeData = Theme.of(context);
    final TextStyle aboutTextStyle = themeData.textTheme.bodyText1!;
    final TextStyle linkStyle =
        aboutTextStyle.copyWith(color: themeData.colorScheme.secondary);

    return AlertDialog(
      title: Text(S.of(context).privacyPolicy),
      content: RichText(
        text: TextSpan(
          children: <TextSpan>[
            TextSpan(
              style: aboutTextStyle,
              text: S.of(context).privacyPolicy_Detail_1,
            ),
            LinkTextSpan(
              style: linkStyle,
              text: S.of(context).eula,
              url: Constants.eulaURL.urlZh,
            ),
            TextSpan(
              style: aboutTextStyle,
              text: S.of(context).and,
            ),
            LinkTextSpan(
              style: linkStyle,
              text: S.of(context).privacyPolicy,
              url: Constants.privacyPolicyURL.urlZh,
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
            _setPrivacyPolicyAccepted();
            Navigator.pop(context);
          },
        ),
        if (!kIsWeb && Platform.isAndroid)
          TextButton(
            child: Text(S.of(context).exit),
            onPressed: () {
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
          ),
      ],
    );
  }
}
