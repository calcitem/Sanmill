// This file is part of Sanmill.
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

package com.calcitem.sanmill;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

import android.content.Context;
import android.net.Uri;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

public class MainActivity extends FlutterActivity {

    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine);

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
                  } else if (call.method.equals("writeContentUri")) {
                      String uriString = call.argument("uri");
                      String content = call.argument("content");
                      Uri uri = Uri.parse(uriString);
                      boolean success = writeContentUri(uri, content, this);
                      if (success) {
                          result.success(true);
                      } else {
                          result.error("WRITE_FAILED", "Failed to write content URI.", null);
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

    public boolean writeContentUri(Uri uri, String content, Context context) {
        try (OutputStream outputStream = context.getContentResolver().openOutputStream(uri)) {
            if (outputStream == null) {
                return false;
            }
            byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
            outputStream.write(bytes);
            outputStream.flush();
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
}
