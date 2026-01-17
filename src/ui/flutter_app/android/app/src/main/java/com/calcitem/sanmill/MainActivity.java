// This file is part of Sanmill.
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
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

import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

import android.content.Context;
import android.net.Uri;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public class MainActivity extends FlutterActivity {

    private static final String ENGINE_CHANNEL = "com.calcitem.sanmill/engine";
    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";

    // Background thread for engine operations to avoid blocking the main thread
    private HandlerThread engineThread;
    private Handler engineHandler;
    private Handler mainHandler;
    private MillEngine engine;

    // You do not need to override onCreate() in order to invoke
    // GeneratedPluginRegistrant. Flutter now does that on your behalf.

    // ...retain whatever custom code you had from before (if any).

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine);

        // Initialize background thread for engine operations.
        // Guard against accidental re-initialization if configureFlutterEngine()
        // is called more than once for the same Activity instance.
        if (engineThread == null) {
            engineThread = new HandlerThread("MillEngineThread");
            engineThread.start();
            engineHandler = new Handler(engineThread.getLooper());
        }

        if (mainHandler == null) {
            mainHandler = new Handler(Looper.getMainLooper());
        }

        if (engine == null) {
            engine = new MillEngine();
        }

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ENGINE_CHANNEL)
                .setMethodCallHandler(
                    (call, result) -> {
                        // Execute all engine operations on background thread to avoid blocking the main thread,
                        // then post the Result callback back to the main thread for safety.
                        final Handler callbackHandler = mainHandler != null
                                ? mainHandler
                                : new Handler(Looper.getMainLooper());

                        if (engineHandler == null || engine == null) {
                            callbackHandler.post(
                                    () -> result.error(
                                            "ENGINE_THREAD_NOT_READY",
                                            "Engine thread not ready.",
                                            null
                                    )
                            );
                            return;
                        }

                        final String method = call.method;
                        final Object args = call.arguments;

                        engineHandler.post(() -> {
                            try {
                                switch (method) {
                                    case "startup":
                                        final int startupRet = engine.startup();
                                        callbackHandler.post(() -> result.success(startupRet));
                                        break;
                                    case "send":
                                        final int sendRet =
                                                engine.send(args == null ? "" : args.toString());
                                        callbackHandler.post(() -> result.success(sendRet));
                                        break;
                                    case "read":
                                        final String readRet = engine.read();
                                        callbackHandler.post(() -> result.success(readRet));
                                        break;
                                    case "shutdown":
                                        final int shutdownRet = engine.shutdown();
                                        callbackHandler.post(() -> result.success(shutdownRet));
                                        break;
                                    case "isReady":
                                        final boolean isReadyRet = engine.isReady();
                                        callbackHandler.post(() -> result.success(isReadyRet));
                                        break;
                                    case "isThinking":
                                        final boolean isThinkingRet = engine.isThinking();
                                        callbackHandler.post(() -> result.success(isThinkingRet));
                                        break;
                                    case "getResponseDroppedCount":
                                        final long droppedCount = engine.getResponseDroppedCount();
                                        callbackHandler.post(() -> result.success(droppedCount));
                                        break;
                                    default:
                                        callbackHandler.post(result::notImplemented);
                                        break;
                                }
                            } catch (Exception e) {
                                final String message = e.getMessage() != null ? e.getMessage() : e.toString();
                                callbackHandler.post(() -> result.error("ENGINE_ERROR", message, null));
                            }
                        });
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
    protected void onDestroy() {
        // Clean up background thread when activity is destroyed
        if (engineThread != null) {
            engineThread.quitSafely();
            try {
                engineThread.join(1000); // Wait up to 1 second for thread to finish
            } catch (InterruptedException e) {
                Log.w("MainActivity", "Engine thread interrupted during shutdown", e);
            }
            engineThread = null;
            engineHandler = null;
        }
        mainHandler = null;
        engine = null;
        super.onDestroy();
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
