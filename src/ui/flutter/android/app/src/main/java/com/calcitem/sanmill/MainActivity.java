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

package com.calcitem.sanmill;

import android.os.Bundle;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterActivity {

    private static final String ENGINE_CHANNEL = "com.calcitem.sanmill/engine";

    private MillEngine engine;

    @Override
    public void onCreate(Bundle savedInstanceState) {

        super.onCreate(savedInstanceState);

        engine = new MillEngine();

        FlutterEngine fe = getFlutterEngine();
        if (fe == null) return;

        MethodChannel methodChannel =
                new MethodChannel(fe.getDartExecutor(), ENGINE_CHANNEL);

        methodChannel.setMethodCallHandler((call, result) -> {

                    switch (call.method) {

                        case "startup":
                            result.success(engine.startup());
                            break;

                        case "send":
                            result.success(engine.send(call.arguments.toString()));
                            break;

                        case "read":
                            result.success(engine.read());
                            break;

                        case "shutdown":
                            result.success(engine.shutdown());
                            break;

                        case "isReady":
                            result.success(engine.isReady());
                            break;

                        case "isThinking":
                            result.success(engine.isThinking());
                            break;

                        default:
                            result.notImplemented();
                            break;
                    }
                }
        );
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {

        GeneratedPluginRegistrant.registerWith(flutterEngine);
    }
}