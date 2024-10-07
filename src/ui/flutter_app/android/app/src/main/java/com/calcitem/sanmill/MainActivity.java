// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

import org.json.JSONObject;
import android.app.Application;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import java.util.Arrays;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import xcrash.TombstoneManager;
import xcrash.TombstoneParser;
import xcrash.XCrash;
import xcrash.ICrashCallback;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;

import android.os.Handler;
import android.os.Looper;

public class MainActivity extends FlutterActivity {

    private static final String ENGINE_CHANNEL = "com.calcitem.sanmill/engine";
    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";

    private final String TAG_XCRASH = "xCrash";

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

        // Initialize xCrash.
        if (Build.VERSION.SDK_INT >= 19) {
            // callback for java crash, native crash and ANR
            ICrashCallback callback = new ICrashCallback() {
                @Override
                public void onCrash(String logPath, String emergency) {
                    Log.d(TAG_XCRASH,
                            "xCrash log path: " + (logPath != null ? logPath : "(null)") + ", " +
                                    "emergency: " + (emergency != null ? emergency : "(null)"));

                    if (emergency != null) {
                        debug(logPath, emergency);

                        // Disk is exhausted, send crash report immediately.
                        sendThenDeleteCrashLog(logPath, emergency);
                    } else {
                        // Add some expanded sections. Send crash report at the next time APP startup.

                        TombstoneManager.appendSection(logPath,
                                "expanded_key_1", "expanded_content");
                        TombstoneManager.appendSection(logPath,
                                "expanded_key_2", "expanded_content_row_1\nexpanded_content_row_2");

                        // Invalid. (Do NOT include multiple consecutive newline characters ("\n\n") in the content string.)
                        // TombstoneManager.appendSection(logPath, "expanded_key_3", "expanded_content_row_1\n\nexpanded_content_row_2");

                        debug(logPath, null);
                    }
                }
            };

            Log.d(TAG_XCRASH, "xCrash SDK init: start");

            XCrash.init(this, new XCrash.InitParameters()
                    .setAppVersion("3.1.0") // TODO
                    .setJavaRethrow(true)
                    .setJavaLogCountMax(10)
                    .setJavaDumpAllThreadsWhiteList(new String[]{"^main$", "^Binder:.*", ".*Finalizer.*"})
                    .setJavaDumpAllThreadsCountMax(10)
                    .setJavaCallback(callback)
                    .setNativeRethrow(true)
                    .setNativeLogCountMax(10)
                    .setNativeDumpAllThreadsWhiteList(new String[]{
                            "^xcrash\\.sample$",
                            "^Signal Catcher$",
                            "^Jit thread pool$",
                            ".*mill.*",
                            ".*engine.*"})   // TODO
                    .setNativeDumpAllThreadsCountMax(10)
                    .setNativeCallback(callback)
                    .setAnrRethrow(true)
                    .setAnrLogCountMax(10)
                    .setAnrCallback(callback)
                    .setPlaceholderCountMax(3)
                    .setPlaceholderSizeKb(512)
                    .setLogDir(getExternalFilesDir("xcrash").toString())
                    .setLogFileMaintainDelayMs(1000));

            Log.d(TAG_XCRASH, "xCrash SDK init: end");
        } else {
            Log.d(TAG_XCRASH, "Skip xCrash SDK init because API minSdkVersion < 19.");
        }

        // Send all pending crash log files.
        new Thread(new Runnable() {
            @Override
            public void run() {
                for(File file : TombstoneManager.getAllTombstones()) {
                    sendThenDeleteCrashLog(file.getAbsolutePath(), null);
                }
            }
        }).start();

        Intent serviceIntent = new Intent(this, MyForegroundService.class);
        startService(serviceIntent);

    }

    private void sendThenDeleteCrashLog(String logPath, String emergency) {
        Log.d(TAG_XCRASH, "Skip sendThenDeleteCrashLog(" + logPath + ", " + emergency);
        // Parse
        //Map<String, String> map = TombstoneParser.parse(logPath, emergency);
        //String crashReport = new JSONObject(map).toString();

        // Send the crash report to server-side.
        // ......

        // If the server-side receives successfully, delete the log file.
        //
        // Note: When you use the placeholder file feature,
        //       please always use this method to delete tombstone files.
        //
        //TombstoneManager.deleteTombstone(logPath);
    }

    private void debug(String logPath, String emergency) {
        // Parse and save the crash info to a JSON file for debugging.
        FileWriter writer = null;
        try {
            File debug = new File(XCrash.getLogDir() + "/debug.json");
            debug.createNewFile();
            writer = new FileWriter(debug, false);
            writer.write(new JSONObject(TombstoneParser.parse(logPath, emergency)).toString());
        } catch (Exception e) {
            Log.d(TAG_XCRASH, "debug failed", e);
        } finally {
            if (writer != null) {
                try {
                    writer.close();
                    Log.d(TAG_XCRASH, "xCrash log files have been written");
                } catch (Exception ignored) {
                }
            }
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
