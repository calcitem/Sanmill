<h1 align="center">camera_desktop</h1>

<p align="center">
<a href="https://flutter.dev"><img src="https://img.shields.io/badge/Platform-Flutter-02569B?logo=flutter" alt="Platform"></a>
<a href="https://dart.dev"><img src="https://img.shields.io/badge/language-Dart-blue" alt="Language: Dart"></a>
<br>
<a href="https://pub.dev/packages/camera_desktop"><img src="https://img.shields.io/pub/v/camera_desktop?label=pub.dev&labelColor=333940&logo=dart" alt="Pub Version"></a>
<a href="https://pub.dev/packages/camera_desktop/score"><img src="https://img.shields.io/pub/points/camera_desktop?color=2E8B57&label=pub%20points" alt="pub points"></a>
<a href="https://github.com/hugocornellier/camera_desktop/actions/workflows/ci.yml"><img src="https://github.com/hugocornellier/camera_desktop/actions/workflows/ci.yml/badge.svg" alt="Flutter CI"></a>
<a href="https://github.com/hugocornellier/camera_desktop/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-007A88.svg" alt="License"></a>
</p>

A Flutter camera plugin for desktop platforms. Implements
[`camera_platform_interface`](https://pub.dev/packages/camera_platform_interface)
so it works seamlessly with the standard
[`camera`](https://pub.dev/packages/camera) package and `CameraController`.

## Platform Support

| Platform | Backend | Status |
|----------|---------|--------|
| **Linux** | GStreamer + V4L2 | Included |
| **macOS** | AVFoundation | Included |
| **Windows** | Media Foundation | Included |

## Installation

Add `camera_desktop` alongside `camera` in your `pubspec.yaml`:

```yaml
dependencies:
  camera: ^0.11.0
  camera_desktop: ^1.2.1
```

That's it. All three desktop platforms are covered, no additional packages needed.

## Usage

Use the standard `camera` package API:

```dart
import 'package:camera/camera.dart';

final cameras = await availableCameras();
final controller = CameraController(cameras.first, ResolutionPreset.high);
await controller.initialize();

// Preview
CameraPreview(controller);

// Capture
final file = await controller.takePicture();

// Record
await controller.startVideoRecording();
final video = await controller.stopVideoRecording();
```

### Advanced Settings

`CameraController` (camera 0.11.x+) accepts optional `fps`, `videoBitrate`, and
`audioBitrate` parameters at construction time:

```dart
final controller = CameraController(
  cameras.first,
  ResolutionPreset.veryHigh,
  enableAudio: true,
  fps: 30,
  videoBitrate: 5000000,   // 5 Mbps
  audioBitrate: 128000,    // 128 kbps
);
```

These settings are applied during `initialize()`. To change them you must
`dispose()` the controller and create a new one, see [Limitations](#limitations).

## Platform-Specific Setup

### Linux

Install GStreamer development libraries:

```bash
# Ubuntu/Debian
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good

# Fedora
sudo dnf install gstreamer1-devel gstreamer1-plugins-base-devel gstreamer1-plugins-good

# Arch
sudo pacman -S gstreamer gst-plugins-base gst-plugins-good
```

### macOS

Add camera and microphone usage descriptions to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for video recording.</string>
```

For sandboxed apps, add to your entitlements:

```xml
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Windows

No additional setup required.

## Features

| Feature | Linux | macOS | Windows |
|---------|-------|-------|---------|
| Camera enumeration | Yes | Yes | Yes |
| Live preview | Yes | Yes | Yes |
| Photo capture | Yes | Yes | Yes |
| Video recording | Yes | Yes | Yes |
| Image streaming | Yes | Yes | No |
| Audio recording | Yes | Yes | Yes |
| Resolution presets | Yes | Yes | Yes |
| Custom FPS | Yes | Yes | Yes |
| Video bitrate control | Yes | Yes | Yes |
| Audio bitrate control | Yes | Yes | Yes |
| Mirror control | Yes | Yes | No (handled in Flutter) |

## Mirror / Flip Behavior

On **macOS** and **Linux**, the preview frames are mirrored at the native capture
level (like a webcam selfie view), so `buildPreview()` returns the texture as-is.
The mirror state can be toggled at runtime via `setMirror()`:

```dart
import 'package:camera_desktop/camera_desktop.dart';

// Toggle mirror at runtime (macOS & Linux only)
final plugin = CameraDesktopPlugin();
await plugin.setMirror(cameraId, false); // disable mirror
await plugin.setMirror(cameraId, true);  // re-enable mirror
```

On **Windows**, the native backend does not mirror, so the example app wraps the
preview in a horizontal `Transform` in Flutter:

```dart
if (Platform.isWindows) {
  return Transform(
    alignment: Alignment.center,
    transform: Matrix4.diagonal3Values(-1, 1, 1),
    child: Texture(textureId: textureId),
  );
}
```

The same applies to video playback. Recorded files from macOS/Linux are already
mirrored, while Windows recordings need a Flutter-side flip if you want a
mirror-style playback.

## Platform Capabilities

Query what the current platform supports at runtime:

```dart
import 'package:camera_desktop/camera_desktop.dart';

final caps = await CameraDesktopPlugin().getPlatformCapabilities();
// caps['supportsMirrorControl'] == true  (macOS & Linux)
// caps['supportsVideoFpsControl'] == true
// caps['supportsVideoBitrateControl'] == true
// caps['supportsAudioBitrateControl'] == true
```

This is useful when building UIs that conditionally expose controls based on the
running platform.

## Limitations

Desktop cameras generally do not support mobile-oriented features:

- Flash/torch control
- Exposure/focus point selection
- Zoom (beyond 1.0x)
- Device orientation changes
- Pause/resume video recording

These methods either no-op or throw `CameraException` as appropriate.

`fps`, `videoBitrate`, and `audioBitrate` are applied at initialization and cannot
be changed on a running controller. To update them, `dispose()` the controller and
create a new one with the desired settings.
