// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// qr_scanner_page.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_screenshot/screenshot.dart';

import '../../generated/intl/l10n.dart';
import 'qr_scanner_temp_png_stub.dart'
    if (dart.library.io) 'qr_scanner_temp_png_io.dart';
import 'qr_selection_page.dart';

enum _CameraState { checking, available, unavailable }

/// Android / iOS: live camera via [ReaderWidget]. Desktop and web: no camera
/// plugin — pick an image file; on Windows, optional full-screen or region
/// capture ([just_screenshot]) then decode.
///
/// Returns the decoded QR string via [Navigator.pop] on successful scan.
/// When multiple QR codes are detected via the camera, freezes the frame,
/// re-analyses it and opens [QrSelectionPage] for the user to tap the code
/// they want. When multiple codes are found in an image the same visual
/// selection page is used.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

bool get _usesLiveCameraScanner {
  if (kIsWeb) {
    return false;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return false;
  }
}

bool get _supportsWindowsScreenCapture {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  bool _hasPopped = false;

  /// True while capturing a still frame and navigating to the selection page.
  bool _isCapturing = false;

  /// True while processing a gallery image or screenshot.
  bool _isDecoding = false;

  _CameraState _cameraState = _CameraState.checking;

  /// Camera controller provided by [ReaderWidget.onControllerCreated].
  CameraController? _cameraController;

  bool get _isBusy => _isCapturing || _isDecoding || _hasPopped;

  /// Incremented to force-recreate the [ReaderWidget] when the camera becomes
  /// unresponsive. Changing the key causes Flutter to discard the old widget
  /// state (disposing the broken camera) and create a fresh one.
  int _readerKey = 0;

  /// True while the camera is being torn down and rebuilt. During this window
  /// the [ReaderWidget] is removed from the tree entirely so the old
  /// [CameraController] can finish its asynchronous disposal before a new one
  /// is created.
  bool _isReinitializing = false;

  /// Tracks whether at least one scan callback has been received, so the
  /// watchdog does not trigger during initial camera warm-up.
  bool _hasReceivedFirstCallback = false;

  /// Timestamp of the most recent scan callback (success or failure).
  DateTime _lastScanActivity = DateTime.now();

  Timer? _watchdogTimer;

  static const Duration _watchdogInterval = Duration(seconds: 2);
  static const Duration _watchdogThreshold = Duration(seconds: 5);

  /// Time to wait for the old [CameraController] to finish async disposal
  /// before creating a new [ReaderWidget].
  static const Duration _cameraReleaseDelay = Duration(milliseconds: 1500);

  DecodeParams get _decodeParamsMulti => DecodeParams(
    imageFormat: ImageFormat.rgb,
    format: Format.qrCode,
    isMultiScan: true,
    tryHarder: true,
    maxSize: 1920,
  );

  DecodeParams get _decodeParamsSingle => DecodeParams(
    imageFormat: ImageFormat.rgb,
    format: Format.qrCode,
    tryHarder: true,
    maxSize: 1920,
  );

  @override
  void initState() {
    super.initState();
    if (_usesLiveCameraScanner) {
      WidgetsBinding.instance.addObserver(this);
      _startWatchdog();
    } else {
      _cameraState = _CameraState.unavailable;
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    if (_usesLiveCameraScanner) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_usesLiveCameraScanner) {
      return;
    }
    if (state == AppLifecycleState.resumed &&
        !_hasPopped &&
        !_isReinitializing) {
      _reinitializeCamera();
    }
  }

  // ── Camera health / watchdog ───────────────────────────────────────

  void _onScanActivity() {
    _hasReceivedFirstCallback = true;
    _lastScanActivity = DateTime.now();
  }

  void _startWatchdog() {
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      if (_hasPopped ||
          _isBusy ||
          !_hasReceivedFirstCallback ||
          _cameraState != _CameraState.available ||
          _isReinitializing) {
        return;
      }
      if (DateTime.now().difference(_lastScanActivity) > _watchdogThreshold) {
        _reinitializeCamera();
      }
    });
  }

  /// Tears down the current [ReaderWidget] (removing it from the tree so the
  /// [CameraController] is fully disposed), waits for the camera hardware to
  /// be released, then creates a fresh [ReaderWidget].
  Future<void> _reinitializeCamera() async {
    if (_isReinitializing || _hasPopped) {
      return;
    }

    _hasReceivedFirstCallback = false;
    _lastScanActivity = DateTime.now();

    setState(() {
      _isReinitializing = true;
    });

    await Future<void>.delayed(_cameraReleaseDelay);

    if (mounted && !_hasPopped) {
      setState(() {
        _cameraState = _CameraState.checking;
        _readerKey++;
        _isReinitializing = false;
      });
    }
  }

  // ── Camera multi-scan callback ──────────────────────────────────────

  /// Called by [ReaderWidget] every frame where at least one code is found.
  void _onMultiScan(Codes codes) {
    _onScanActivity();
    if (_isBusy) {
      return;
    }

    final List<Code> valid = codes.codes
        .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
        .toList();

    if (valid.isEmpty) {
      return;
    }

    if (valid.length == 1) {
      _hasPopped = true;
      Navigator.of(context).pop(valid.first.text);
      return;
    }

    _captureAndSelect();
  }

  // ── Camera capture & selection flow ─────────────────────────────────

  /// Stops the image stream, takes a still picture, re-analyses it and opens
  /// [QrSelectionPage]. Stopping the stream before [takePicture] is required
  /// on Android; the stream is not restarted because the page pops after
  /// selection (or the ReaderWidget reinitialises on resume if cancelled).
  Future<void> _captureAndSelect() async {
    if (_cameraController == null || _isBusy) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      if (_cameraController!.value.isStreamingImages) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {
          // Ignore; best-effort stop.
        }
      }

      late final XFile picture;
      try {
        picture = await _cameraController!.takePicture();
      } catch (_) {
        return;
      }

      final Uint8List imageBytes = await picture.readAsBytes();

      late final Codes freshCodes;
      try {
        freshCodes = await zx.readBarcodesImagePath(
          picture,
          DecodeParams(
            imageFormat: ImageFormat.rgb,
            format: Format.qrCode,
            isMultiScan: true,
            tryHarder: true,
            maxSize: 1920,
          ),
        );
      } catch (_) {
        return;
      }

      final List<Code> valid = freshCodes.codes
          .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
          .toList();

      if (!mounted || valid.isEmpty) {
        return;
      }

      if (valid.length == 1) {
        _hasPopped = true;
        Navigator.of(context).pop(valid.first.text);
        return;
      }

      final String? selected = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => QrSelectionPage(imageBytes: imageBytes, codes: valid),
        ),
      );

      if (selected != null && selected.isNotEmpty && mounted) {
        _hasPopped = true;
        Navigator.of(context).pop(selected);
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  // ── Decode from image file / screenshot bytes ───────────────────────

  Future<void> _handleDecodedCodes(
    List<Code> valid,
    Uint8List imageBytes,
  ) async {
    if (valid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).qrCodeNotFoundInImage)),
        );
      }
      return;
    }

    if (valid.length == 1) {
      _hasPopped = true;
      Navigator.of(context).pop(valid.first.text);
      return;
    }

    final String? selected = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => QrSelectionPage(imageBytes: imageBytes, codes: valid),
      ),
    );

    if (selected != null && selected.isNotEmpty && mounted) {
      _hasPopped = true;
      Navigator.of(context).pop(selected);
    }
  }

  Future<void> _decodeFromXFile(XFile file) async {
    final Uint8List imageBytes = await file.readAsBytes();

    late final Codes codes;
    try {
      codes = await zx.readBarcodesImagePath(file, _decodeParamsMulti);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).qrCodeNotFoundInImage)),
        );
      }
      return;
    }

    List<Code> valid = codes.codes
        .where((Code c) => c.isValid && c.text != null && c.text!.isNotEmpty)
        .toList();

    if (valid.isEmpty) {
      try {
        final Code single = await zx.readBarcodeImagePath(
          file,
          _decodeParamsSingle,
        );
        if (single.isValid && single.text != null && single.text!.isNotEmpty) {
          valid = <Code>[single];
        }
      } catch (_) {
        // Image could not be decoded; fall through to "not found" handling.
      }
    }

    if (!mounted) {
      return;
    }

    await _handleDecodedCodes(valid, imageBytes);
  }

  /// Writes [pngBytes] to a temp file and reuses the same decode path as
  /// [readBarcodesImagePath] (handles PNG / JPEG via the image package).
  Future<void> _decodeFromPngBytes(Uint8List pngBytes) async {
    await decodePngBytesWithTempFile(pngBytes, _decodeFromXFile);
  }

  Future<void> _windowsScreenshot(ScreenshotMode mode) async {
    if (!_supportsWindowsScreenCapture || _isBusy) {
      return;
    }

    setState(() => _isDecoding = true);

    try {
      final CapturedData? data = await Screenshot.instance.capture(mode: mode);
      if (!mounted || data == null) {
        return;
      }
      await _decodeFromPngBytes(data.bytes);
    } on ScreenshotException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${S.of(context).qrCodeScreenCaptureFailed}: ${e.message}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
    }
  }

  // ── Gallery / file import ──────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_isBusy) {
      return;
    }

    setState(() => _isDecoding = true);

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );

      if (file == null) {
        return;
      }

      await _decodeFromXFile(file);
    } finally {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
    }
  }

  // ── Desktop / web UI (no [ReaderWidget], no camera channel) ────────

  Widget _buildDesktopScannerBody(S s) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.qr_code_scanner,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              s.qrCodeScannerDesktopHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: Text(s.qrCodePickImageFile),
              onPressed: _isDecoding ? null : _pickFromGallery,
            ),
            if (_supportsWindowsScreenCapture) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                s.qrCodeScannerWindowsScreenCaptureHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.crop_free),
                label: Text(s.qrCodeSnipScreenRegion),
                onPressed: _isDecoding
                    ? null
                    : () => _windowsScreenshot(ScreenshotMode.region),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.screenshot_monitor_outlined),
                label: Text(s.qrCodeCaptureFullScreen),
                onPressed: _isDecoding
                    ? null
                    : () => _windowsScreenshot(ScreenshotMode.screen),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── No-camera fallback (mobile): still must not rely on removing
  /// [ReaderWidget] entirely due to flutter_zxing dispose ordering; desktop
  /// never mounts it (see [build]).
  Widget _buildNoCameraBody(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.no_photography_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              s.noCameraAvailable,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.qrCodeFromGallery),
              onPressed: _pickFromGallery,
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  Widget _buildReaderWidget() {
    return ReaderWidget(
      key: ValueKey<int>(_readerKey),
      codeFormat: Format.qrCode,
      isMultiScan: true,
      showScannerOverlay: false,
      showGallery: false,
      showToggleCamera: false,
      tryHarder: true,
      scanDelay: const Duration(milliseconds: 500),
      onControllerCreated: (CameraController? controller, Exception? error) {
        _cameraController = controller;
        if (mounted) {
          setState(() {
            _cameraState = (error != null || controller == null)
                ? _CameraState.unavailable
                : _CameraState.available;
          });
        }
      },
      onMultiScan: _onMultiScan,
      onMultiScanFailure: (_) => _onScanActivity(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    if (!_usesLiveCameraScanner) {
      return Scaffold(
        appBar: AppBar(
          title: Text(s.scanQrCode),
          actions: <Widget>[
            if (_isDecoding)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: _buildDesktopScannerBody(s),
      );
    }

    // flutter_zxing's ReaderWidget has a known bug in _stopCamera(): the
    // isStreamingImages condition is inverted, so stopImageStream() is called
    // even when the camera was never streaming. To work around this we keep
    // the ReaderWidget in the widget tree via Offstage rather than removing it
    // when the camera reports unavailability.
    final Widget body;

    if (_isReinitializing) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_hasPopped) {
      final Widget readerWidget = _buildReaderWidget();
      body = Stack(
        children: <Widget>[
          Offstage(child: readerWidget),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    } else if (_cameraState == _CameraState.unavailable) {
      final Widget readerWidget = _buildReaderWidget();
      body = Stack(
        children: <Widget>[
          Offstage(child: readerWidget),
          if (_isDecoding)
            const Center(child: CircularProgressIndicator())
          else
            _buildNoCameraBody(s),
        ],
      );
    } else {
      body = _buildReaderWidget();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.scanQrCode),
        actions: <Widget>[
          if (_isDecoding || _isCapturing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_cameraState != _CameraState.checking && !_isReinitializing)
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: s.qrCodeFromGallery,
              onPressed: _pickFromGallery,
            ),
        ],
      ),
      body: body,
    );
  }
}
