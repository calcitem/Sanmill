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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/l10n.dart';

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
                      fontSize: 16,
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
