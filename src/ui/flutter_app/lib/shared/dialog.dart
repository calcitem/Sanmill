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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:url_launcher/url_launcher.dart';

int _counter = 0;
Timer? _timer;

void startTimer(int counter, StreamController<int> events) {
  _counter = counter;
  if (_timer != null) {
    _timer!.cancel();
  }
  _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
    (_counter > 0) ? _counter-- : _timer!.cancel();
    events.add(_counter);
  });
}

void showCountdownDialog(
  BuildContext ctx,
  int seconds,
  StreamController<int> events,
  void Function() fun,
) {
  final alert = AlertDialog(
    content: StreamBuilder<int>(
      stream: events.stream,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        debugPrint("Count down: ${snapshot.data}");

        if (snapshot.data == 0) {
          fun();
          if (Platform.isAndroid) {
            SystemChannels.platform.invokeMethod('SystemNavigator.pop');
          } else {}
        }

        return SizedBox(
          height: 128,
          child: Column(
            children: <Widget>[
              Text(
                snapshot.data != null ? snapshot.data.toString() : "10",
                style: const TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                },
                child: Center(
                  child: Text(
                    S.of(ctx).cancel,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: LocalDatabaseService.display.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
            },
        );
}

Future<void> showPrivacyDialog(
  BuildContext context,
  Function(bool value) setPrivacyPolicyAccepted,
) async {
  String? locale = "en_US";
  late String eulaURL;
  late String privacyPolicyURL;
  if (!Platform.isWindows) {
    locale = await Devicelocale.currentLocale;
  }

  debugPrint("[about] local = $locale");
  if (locale != null && locale.startsWith("zh_")) {
    eulaURL = Constants.giteeEulaURL;
    privacyPolicyURL = Constants.giteePrivacyPolicyURL;
  } else {
    eulaURL = Constants.githubEulaURL;
    privacyPolicyURL = Constants.githubPrivacyPolicyURL;
  }

  final ThemeData themeData = Theme.of(context);
  final TextStyle? aboutTextStyle = themeData.textTheme.bodyText1;
  final TextStyle linkStyle = themeData.textTheme.bodyText1!
      .copyWith(color: themeData.colorScheme.secondary);

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
            Navigator.pop(context);
          },
        ),
        if (Platform.isAndroid)
          TextButton(
            child: Text(S.of(context).exit),
            onPressed: () {
              setPrivacyPolicyAccepted(false);
              SystemChannels.platform.invokeMethod('SystemNavigator.pop');
            },
          ),
      ],
    ),
  );
}
