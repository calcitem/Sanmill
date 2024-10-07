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

// Import Bluetooth libraries
import java.util.UUID;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.os.ParcelUuid;

import android.os.Handler;
import android.os.Looper;

public class MainActivity extends FlutterActivity {

    private static final String ENGINE_CHANNEL = "com.calcitem.sanmill/engine";
    private static final String NATIVE_CHANNEL = "com.calcitem.sanmill/native";
    private static final String ADVERTISE_CHANNEL = "com.calcitem.sanmill/advertise";
    private static final String ADVERTISE_EVENTS_CHANNEL = "com.calcitem.sanmill/advertise_events";
    private BluetoothDevice connectedDevice;
    private BluetoothLeAdvertiser bluetoothLeAdvertiser;
    private BluetoothGattServer gattServer;
    private EventChannel.EventSink advertiseEventSink; // For sending events to Flutter
    private boolean isAdvertising = false; // To track advertising state

    private final String TAG_XCRASH = "xCrash";

    // Define UUID for advertising (replace with your own UUID)
    private static final String SERVICE_UUID = "123e4567-e89b-12d3-a456-426614174000";

    // Handler to post tasks to the main thread
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // BLE Advertise callback
    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override
        public void onStartSuccess(AdvertiseSettings settingsInEffect) {
            Log.i("BLE", "Advertising started successfully");
            if (advertiseEventSink != null) {
                // Post to main thread to avoid threading issues
                mainHandler.post(() -> {
                    advertiseEventSink.success("Advertising started successfully");
                });
            }
        }

        @Override
        public void onStartFailure(int errorCode) {
            String errorMessage;
            switch (errorCode) {
                case AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE:
                    errorMessage = "Failed to start advertising as the advertise data to be broadcasted is larger than 31 bytes.";
                    break;
                case AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS:
                    errorMessage = "Failed to start advertising because no advertising instance is available.";
                    break;
                case AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED:
                    errorMessage = "Failed to start advertising as the advertising is already started.";
                    break;
                case AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR:
                    errorMessage = "Operation failed due to an internal error.";
                    break;
                case AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED:
                    errorMessage = "This feature is not supported on this platform.";
                    break;
                default:
                    errorMessage = "Unknown error.";
                    break;
            }
            Log.e("BLE", "Advertising failed with error code: " + errorCode + " - " + errorMessage);
            if (advertiseEventSink != null) {
                // Post to main thread to avoid threading issues
                mainHandler.post(() -> {
                    advertiseEventSink.error("ADVERTISE_START_FAILURE", errorMessage, null);
                });
            }
            isAdvertising = false; // Update advertising state
        }
    };

    private void startAdvertising() {
        if (isAdvertising) {
            Log.w("BLE", "Already advertising");
            return;
        }

        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
        if (bluetoothAdapter != null && bluetoothAdapter.isEnabled()) {
            bluetoothLeAdvertiser = bluetoothAdapter.getBluetoothLeAdvertiser();

            // Set up GATT server
            gattServer = bluetoothManager.openGattServer(this, gattServerCallback);
            BluetoothGattService service = new BluetoothGattService(UUID.fromString(SERVICE_UUID), BluetoothGattService.SERVICE_TYPE_PRIMARY);

            // Add characteristics to the service
            BluetoothGattCharacteristic characteristic = new BluetoothGattCharacteristic(
                UUID.fromString(SERVICE_UUID),
                BluetoothGattCharacteristic.PROPERTY_READ | BluetoothGattCharacteristic.PROPERTY_WRITE | BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ | BluetoothGattCharacteristic.PERMISSION_WRITE);

            characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);

            service.addCharacteristic(characteristic);

            // Add the service to the GATT server
            gattServer.addService(service);

            // Define advertise settings
            AdvertiseSettings settings = new AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                    .setConnectable(true)
                    .build();

            // Optionally include a shortened device name to reduce size
            String deviceName = bluetoothAdapter.getName();
            if (deviceName == null || deviceName.length() > 8) {
                deviceName = "BLEDev"; // Short default name
                bluetoothAdapter.setName(deviceName);
            }

            // Define advertise data and include the service UUID
            AdvertiseData advertiseData = new AdvertiseData.Builder()
                    .setIncludeDeviceName(true)
                    .addServiceUuid(new ParcelUuid(UUID.fromString(SERVICE_UUID)))
                    .build();

            // Since we moved the service UUID to the advertise data, we can leave scan response empty or use it for additional data
            AdvertiseData scanResponseData = new AdvertiseData.Builder()
                    .build();

            // Start advertising
            if (bluetoothLeAdvertiser != null) {
                bluetoothLeAdvertiser.startAdvertising(settings, advertiseData, scanResponseData, advertiseCallback);
                isAdvertising = true; // Update advertising state
            } else {
                Log.e("BLE", "Bluetooth LE Advertiser not available");
            }
        } else {
            Log.e("BLE", "Bluetooth Adapter not available or not enabled");
        }
    }

    private void stopAdvertising() {
        if (!isAdvertising) {
            Log.w("BLE", "Not advertising");
            return;
        }

        if (bluetoothLeAdvertiser != null) {
            bluetoothLeAdvertiser.stopAdvertising(advertiseCallback);
            isAdvertising = false;
        }
        if (gattServer != null) {
            gattServer.close();
        }
        Log.i("BLE", "Advertising stopped");
    }

    private void sendMoveToConnectedDevice(String move) {
        Log.d("GATT", "Sending move to connected device: " + move);
        if (gattServer != null && connectedDevice != null) {
            // Retrieve the characteristic associated with the specified UUID
            BluetoothGattCharacteristic characteristic = gattServer
                    .getService(UUID.fromString(SERVICE_UUID))
                    .getCharacteristic(UUID.fromString(SERVICE_UUID));

            // Set the value for the characteristic
            characteristic.setValue(move.getBytes(StandardCharsets.UTF_8));

            // Notify the connected device that the characteristic value has changed
            boolean notificationSent = gattServer.notifyCharacteristicChanged(connectedDevice, characteristic, true);

            // Log the outcome of the notification attempt
            if (notificationSent) {
                Log.i("GATT", "Notification sent successfully");
            } else {
                Log.e("GATT", "Failed to send notification");
            }
        } else {
            Log.w("GATT", "GATT server or connected device is null.");
        }
    }

    private BluetoothGattServerCallback gattServerCallback = new BluetoothGattServerCallback() {
        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            super.onConnectionStateChange(device, status, newState);
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.i("GATT", "Device connected: " + device.getAddress());
                connectedDevice = device;

                new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    sendMoveToConnectedDevice("Your Message Here");
                }, 500);

                if (advertiseEventSink != null) {
                    mainHandler.post(() -> {
                        advertiseEventSink.success("Device connected: " + device.getAddress());
                    });
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.i("GATT", "Device disconnected: " + device.getAddress());
                connectedDevice = null;

                if (advertiseEventSink != null) {
                    mainHandler.post(() -> {
                        advertiseEventSink.success("Device disconnected: " + device.getAddress());
                    });
                }
            }
        }

        @Override
        public void onCharacteristicReadRequest(BluetoothDevice device, int requestId,
                                                int offset, BluetoothGattCharacteristic characteristic) {
            super.onCharacteristicReadRequest(device, requestId, offset, characteristic);
            // Handle read request
            Log.i("GATT", "onCharacteristicReadRequest");
            byte[] value = "Hello from server".getBytes(StandardCharsets.UTF_8);
            gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value);
        }

        @Override
        public void onCharacteristicWriteRequest(BluetoothDevice device, int requestId,
                                                 BluetoothGattCharacteristic characteristic,
                                                 boolean preparedWrite, boolean responseNeeded,
                                                 int offset, byte[] value) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite,
                    responseNeeded, offset, value);
            // Handle write request
            String received = new String(value, StandardCharsets.UTF_8);
            Log.i("GATT", "onCharacteristicWriteRequest, value: " + received);

            if (responseNeeded) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null);
            }

            // If you need to send data to Flutter, ensure to post it to the main thread
            if (advertiseEventSink != null) {
                mainHandler.post(() -> {
                    advertiseEventSink.success("Received data: " + received);
                });
            }

        }
    };

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

        // Setup the new channel for advertising
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ADVERTISE_CHANNEL)
        .setMethodCallHandler((call, result) -> {
            if (call.method.equals("startAdvertising")) {
                startAdvertising();
                result.success("Advertising started");
            } else if (call.method.equals("stopAdvertising")) {
                stopAdvertising();
                result.success("Advertising stopped");
            } else if (call.method.equals("sendMove")) {
                String move = call.argument("move");
                sendMoveToConnectedDevice(move);
                result.success("Move sent: " + move);
            } else {
                result.notImplemented();
            }
        });

        // EventChannel for sending events to Flutter
        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ADVERTISE_EVENTS_CHANNEL)
            .setStreamHandler(new EventChannel.StreamHandler() {
                @Override
                public void onListen(Object arguments, EventChannel.EventSink events) {
                    advertiseEventSink = events;
                }

                @Override
                public void onCancel(Object arguments) {
                    advertiseEventSink = null;
                }
            });
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
