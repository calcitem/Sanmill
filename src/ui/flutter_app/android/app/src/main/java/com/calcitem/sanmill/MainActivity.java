// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

package com.calcitem.sanmill;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.core.view.WindowCompat;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public class MainActivity extends FlutterActivity {

    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";
    private static final String DIAGNOSTICS_CHANNEL =
        "com.calcitem.sanmill/diagnostics";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), true);
        super.onCreate(savedInstanceState);
    }

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

        new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            DIAGNOSTICS_CHANNEL)
            .setMethodCallHandler(
                (call, result) -> {
                    if (!call.method.equals("getSigningCertificateSha256")) {
                        result.notImplemented();
                        return;
                    }
                    try {
                        result.success(getSigningCertificateSha256());
                    } catch (Exception error) {
                        result.error(
                            "SIGNING_DIGEST_FAILED",
                            "Unable to inspect the installed app signature.",
                            null);
                    }
                });
    }

    @SuppressWarnings("deprecation")
    private String getSigningCertificateSha256() throws Exception {
        PackageManager packageManager = getPackageManager();
        PackageInfo packageInfo;
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo = packageManager.getPackageInfo(
                getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
            signatures = packageInfo.signingInfo == null
                ? null
                : packageInfo.signingInfo.getApkContentsSigners();
        } else {
            packageInfo = packageManager.getPackageInfo(
                getPackageName(), PackageManager.GET_SIGNATURES);
            signatures = packageInfo.signatures;
        }
        if (signatures == null || signatures.length == 0) {
            return null;
        }
        byte[] digest = MessageDigest.getInstance("SHA-256")
            .digest(signatures[0].toByteArray());
        StringBuilder encoded = new StringBuilder(digest.length * 2);
        for (byte value : digest) {
            encoded.append(String.format("%02x", value & 0xff));
        }
        return encoded.toString();
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
