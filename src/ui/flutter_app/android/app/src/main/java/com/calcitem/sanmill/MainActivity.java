// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

package com.calcitem.sanmill;

import android.os.Bundle;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

import org.json.JSONObject;
import android.app.Application;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public class MainActivity extends FlutterActivity {

    private static final String ENGINE_CHANNEL = "com.calcitem.sanmill/engine";
    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";

    // You do not need to override onCreate() in order to invoke
    // GeneratedPluginRegistrant. Flutter now does that on your behalf.

    // ...retain whatever custom code you had from before (if any).

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ENGINE_CHANNEL)
                .setMethodCallHandler(
                    (call, result) -> {
                        MillEngine engine = new MillEngine();
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

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), NATIVE_CHANNEL)
            .setMethodCallHandler(
              (call, result) -> {
                  if (call.method.equals("readContentUri")) {
                      String uriString = call.argument("uri");
                      Uri uri = Uri.parse(uriString);
                      String data;
                      if ("content".equals(uri.getScheme())) {
                          data = readContentUri(uri, this);
                      } else if ("file".equals(uri.getScheme())) {
                          data = readFileUri(uri, this);
                      } else {
                          data = null;
                      }
                      if (data != null) {
                          result.success(data);
                      } else {
                          result.error("UNAVAILABLE", "Data not available.", null);
                      }
                  } else {
                      result.notImplemented();
                  }
            }
        );
    }

    @Override
    protected void attachBaseContext(Context base) {
        if (base != null) {
            super.attachBaseContext(base);
        }
    }

    public String readContentUri(Uri uri, Context context) {
        try {
            InputStream inputStream = context.getContentResolver().openInputStream(uri);
            byte[] bytes = new byte[inputStream.available()];
            inputStream.read(bytes);
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public String readFileUri(Uri uri, Context context) {
        File file = new File(uri.getPath());
        try (FileInputStream fileInputStream = new FileInputStream(file)) {
            byte[] bytes = new byte[fileInputStream.available()];
            fileInputStream.read(bytes);
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }
}
