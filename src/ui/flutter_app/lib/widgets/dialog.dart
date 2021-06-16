/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:async';
import 'dart:io';

import 'package:devicelocale/devicelocale.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

int _counter = 0;
Timer? _timer;

void startTimer(var counter, var events) {
  _counter = counter;
  if (_timer != null) {
    _timer!.cancel();
  }
  _timer = Timer.periodic(Duration(seconds: 1), (timer) {
    (_counter > 0) ? _counter-- : _timer!.cancel();
    events.add(_counter);
  });
}

void showCountdownDialog(
    BuildContext ctx, var seconds, var events, void fun()) {
  var alert = AlertDialog(
    content: StreamBuilder<int>(
      stream: events.stream,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        print("Count down: " + snapshot.data.toString());

        if (snapshot.data == 0) {
          fun();
          if (Platform.isAndroid) {
            SystemChannels.platform.invokeMethod('SystemNavigator.pop');
          } else {}
        }

        return Container(
          height: 128,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                snapshot.data != null ? '${snapshot.data.toString()}' : "10",
                style: TextStyle(fontSize: 64),
              ),
              SizedBox(
                height: 20,
              ),
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  child: Center(
                      child: Text(
                    S.of(ctx).cancel,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: Config.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  )),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  startTimer(seconds, events);

  showDialog(
    context: ctx,
    builder: (BuildContext c) {
      return alert;
    },
  );
}

class _LinkTextSpan extends TextSpan {
  _LinkTextSpan({TextStyle? style, required String url, String? text})
      : super(
            style: style,
            text: text ?? url,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                launch(url, forceSafariVC: false);
              });
}

showPrivacyDialog(
    BuildContext context, setPrivacyPolicyAccepted(bool value)) async {
  String? locale = "en_US";
  late String eulaURL;
  late String privacyPolicyURL;
  if (!Platform.isWindows) {
    locale = await Devicelocale.currentLocale;
  }

  print("[about] local = $locale");
  if (locale != null && locale.startsWith("zh_")) {
    eulaURL = 'https://gitee.com/calcitem/Sanmill/wikis/EULA_zh';
    privacyPolicyURL =
        'https://gitee.com/calcitem/Sanmill/wikis/privacy_policy_zh';
  } else {
    eulaURL = 'https://github.com/calcitem/Sanmill/wiki/EULA';
    privacyPolicyURL =
        'https://github.com/calcitem/Sanmill/wiki/privacy_policy';
  }

  final ThemeData themeData = Theme.of(context);
  final TextStyle? aboutTextStyle = themeData.textTheme.bodyText1;
  final TextStyle linkStyle =
      themeData.textTheme.bodyText1!.copyWith(color: themeData.accentColor);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(
        S.of(context).privacyPolicy,
      ),
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
            setPrivacyPolicyAccepted(true);
            Navigator.of(context).pop();
          },
        ),
        Platform.isAndroid
            ? TextButton(
                child: Text(S.of(context).exit),
                onPressed: () {
                  setPrivacyPolicyAccepted(false);
                  SystemChannels.platform.invokeMethod('SystemNavigator.pop');
                },
              )
            : Container(height: 0.0, width: 0.0),
      ],
    ),
  );
}
