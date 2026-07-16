// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// config_import_export_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/models/display_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';

/// Non-cancel import failures (user-facing text comes from l10n via [errorKind]).
enum ConfigImportErrorKind { fileNotFound, invalidFile, readFailed }

/// Result of a config import operation.
class ConfigImportResult {
  const ConfigImportResult({
    required this.success,
    this.mediaCount = 0,
    this.userCancelled = false,
    this.errorKind,
  });

  final bool success;
  final int mediaCount;

  /// User closed the file picker without choosing a file — not an error.
  final bool userCancelled;

  /// Set when [success] is false and [userCancelled] is false.
  final ConfigImportErrorKind? errorKind;
}

/// Exports and imports all application settings as a self-contained ZIP
/// archive.  The archive bundles a `settings.json` with every user-uploaded
/// media file (custom board / piece / background images, background music)
/// so the configuration is fully portable across devices.
class ConfigImportExportService {
  const ConfigImportExportService._();

  static const String _logTag = '[config_io]';
  static const String formatVersion = '1.0';
  static const String fileExtension = 'sanmill_config';
  static const String _settingsFileName = 'settings.json';
  static const String _mediaDir = 'media';

  // ────────────────────────────── Export ──────────────────────────────

  /// Build a ZIP archive containing all settings and custom media.
  /// Returns the temporary file path on success, `null` on failure.
  static Future<String?> exportConfig() async {
    try {
      final Archive archive = Archive();

      final Map<String, dynamic> generalJson = DB().generalSettings.toJson();
      final Map<String, dynamic> ruleJson = DB().ruleSettings.toJson();
      final Map<String, dynamic> displayJson = DB().displaySettings.toJson();
      final Map<String, dynamic> colorJson = DB().colorSettings.toJson();

      // Strip sensitive / device-local fields.
      // JSON keys use PascalCase due to field_rename: pascal in build.yaml.
      _removeLlmFields(generalJson);
      generalJson.remove('LastPgnSaveDirectory');

      // Pack user-uploaded media into the archive and replace absolute
      // paths in the JSON maps with archive-relative paths.
      await _packMedia(archive, displayJson, generalJson);

      final Map<String, dynamic> exportData = <String, dynamic>{
        'formatVersion': formatVersion,
        'exportDate': DateTime.now().toIso8601String(),
        'generalSettings': generalJson,
        'ruleSettings': ruleJson,
        'displaySettings': displayJson,
        'colorSettings': colorJson,
      };

      final List<int> jsonBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(exportData),
      );
      archive.addFile(
        ArchiveFile(_settingsFileName, jsonBytes.length, jsonBytes),
      );

      final List<int> encoded = ZipEncoder().encode(archive);
      final Directory tempDir = await getTemporaryDirectory();
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      final File zipFile = File(
        p.join(tempDir.path, 'sanmill_config_$ts.$fileExtension'),
      );
      await zipFile.writeAsBytes(encoded);

      logger.i('$_logTag Exported config to ${zipFile.path}');
      return zipFile.path;
    } catch (e) {
      logger.e('$_logTag Export failed: $e');
      return null;
    }
  }

  /// Exports settings: on desktop (Windows / Linux / macOS) opens a native
  /// save dialog; on mobile and web uses the system share sheet.
  ///
  /// Returns `null` when the user cancels the desktop save dialog (not an
  /// error).  On mobile / web, success follows [ShareResultStatus.success].
  static Future<bool?> shareConfig({
    required String shareSubject,
    required String saveDialogTitle,
  }) async {
    final String? tempPath = await exportConfig();
    if (tempPath == null) {
      return false;
    }

    final File tempFile = File(tempPath);
    final bool desktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    if (desktop) {
      try {
        final String defaultFileName =
            'sanmill_config_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final Uint8List archiveBytes = await tempFile.readAsBytes();
        final String? outputPath = await FilePicker.saveFile(
          dialogTitle: saveDialogTitle,
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: <String>[fileExtension],
          bytes: archiveBytes,
        );

        if (outputPath == null) {
          await tempFile.delete();
          return null;
        }

        String dest = outputPath;
        final String lower = dest.toLowerCase();
        if (!lower.endsWith('.$fileExtension')) {
          final File savedFile = File(dest);
          assert(savedFile.existsSync(), 'Saved config archive is missing.');
          dest = '$dest.$fileExtension';
          await savedFile.rename(dest);
        }

        await tempFile.delete();
        logger.i('$_logTag Exported config to $dest');
        return true;
      } catch (e) {
        logger.e('$_logTag Desktop save failed: $e');
        try {
          await tempFile.delete();
        } catch (_) {}
        return false;
      }
    }

    try {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(tempPath)], subject: shareSubject),
      );
      return result.status == ShareResultStatus.success;
    } catch (e) {
      logger.e('$_logTag Share failed: $e');
      return false;
    }
  }

  /// Exports settings as an uncompressed JSON file without any media.
  /// Strips sensitive and device-local fields and clears custom media
  /// paths so no private files leave the device.
  /// Returns the temporary file path on success, `null` on failure.
  static Future<String?> exportSettingsJsonOnly() async {
    try {
      final Map<String, dynamic> generalJson = DB().generalSettings.toJson();
      final Map<String, dynamic> ruleJson = DB().ruleSettings.toJson();
      final Map<String, dynamic> displayJson = DB().displaySettings.toJson();
      final Map<String, dynamic> colorJson = DB().colorSettings.toJson();

      // Strip sensitive / device-local fields.
      _removeLlmFields(generalJson);
      generalJson.remove('LastPgnSaveDirectory');

      // Remove custom media paths (always device-local).
      displayJson.remove(_kCustomBg);
      displayJson.remove(_kCustomBoard);
      displayJson.remove(_kCustomWhite);
      displayJson.remove(_kCustomBlack);
      generalJson.remove(_kBgMusic);

      // Clear active media paths that point to device-local files
      // (i.e. not built-in asset paths starting with 'assets/').
      for (final String key in <String>[
        _kActiveBg,
        _kActiveBoard,
        _kActiveWhite,
        _kActiveBlack,
      ]) {
        final dynamic v = displayJson[key];
        if (v is String && v.isNotEmpty && !v.startsWith('assets/')) {
          displayJson[key] = '';
        }
      }

      final Map<String, dynamic> exportData = <String, dynamic>{
        'formatVersion': formatVersion,
        'exportDate': DateTime.now().toIso8601String(),
        'generalSettings': generalJson,
        'ruleSettings': ruleJson,
        'displaySettings': displayJson,
        'colorSettings': colorJson,
      };

      final String jsonStr = const JsonEncoder.withIndent(
        '  ',
      ).convert(exportData);
      final Directory tempDir = await getTemporaryDirectory();
      final File jsonFile = File(p.join(tempDir.path, _settingsFileName));
      await jsonFile.writeAsString(jsonStr, flush: true);

      logger.i('$_logTag Exported settings JSON to ${jsonFile.path}');
      return jsonFile.path;
    } catch (e) {
      logger.e('$_logTag Settings JSON export failed: $e');
      return null;
    }
  }

  // ────────────────────────────── Import ──────────────────────────────

  /// Let the user pick a `.sanmill_config` file and import it.
  static Future<ConfigImportResult> importConfig() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles();

      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return const ConfigImportResult(success: false, userCancelled: true);
      }

      return importConfigFromPath(result.files.single.path!);
    } catch (e) {
      logger.e('$_logTag Import file pick failed: $e');
      return const ConfigImportResult(
        success: false,
        errorKind: ConfigImportErrorKind.readFailed,
      );
    }
  }

  /// Import from a known file path (e.g. share-intent or testing).
  /// Accepts both `.sanmill_config` ZIP archives and plain JSON files.
  static Future<ConfigImportResult> importConfigFromPath(
    String filePath,
  ) async {
    try {
      final File file = File(filePath);
      if (!file.existsSync()) {
        return const ConfigImportResult(
          success: false,
          errorKind: ConfigImportErrorKind.fileNotFound,
        );
      }

      // Try ZIP archive first (the primary .sanmill_config format).
      // Fall through to plain-JSON parsing when ZIP decoding fails.
      try {
        final Uint8List zipBytes = await file.readAsBytes();
        final Archive archive = ZipDecoder().decodeBytes(zipBytes);

        ArchiveFile? settingsFile;
        for (final ArchiveFile f in archive) {
          if (f.name == _settingsFileName && f.isFile) {
            settingsFile = f;
            break;
          }
        }

        if (settingsFile != null) {
          final String jsonStr = utf8.decode(settingsFile.content as List<int>);
          return await _importFromJsonString(jsonStr, archive: archive);
        }
      } catch (_) {
        // Not a valid ZIP archive; fall through to plain-JSON parsing.
      }

      // Try as plain JSON (e.g. a settings.json exported without media).
      final String jsonStr = await file.readAsString();
      return await _importFromJsonString(jsonStr);
    } catch (e) {
      logger.e('$_logTag Import failed: $e');
      return const ConfigImportResult(
        success: false,
        errorKind: ConfigImportErrorKind.readFailed,
      );
    }
  }

  // ───────────────────── Media packing (export) ─────────────────────

  // JSON keys are PascalCase because build.yaml sets field_rename: pascal
  // for json_serializable globally.  All hardcoded key strings here must
  // match that casing exactly or the map lookups silently return null.
  static const String _kCustomBg = 'CustomBackgroundImagePath';
  static const String _kActiveBg = 'BackgroundImagePath';
  static const String _kCustomBoard = 'CustomBoardImagePath';
  static const String _kActiveBoard = 'BoardImagePath';
  static const String _kCustomWhite = 'CustomWhitePieceImagePath';
  static const String _kActiveWhite = 'WhitePieceImagePath';
  static const String _kCustomBlack = 'CustomBlackPieceImagePath';
  static const String _kActiveBlack = 'BlackPieceImagePath';
  static const String _kBgMusic = 'BackgroundMusicFilePath';

  static Future<void> _packMedia(
    Archive archive,
    Map<String, dynamic> displayJson,
    Map<String, dynamic> generalJson,
  ) async {
    await _packImageField(
      archive,
      displayJson,
      _kCustomBg,
      _kActiveBg,
      'custom_background',
    );
    await _packImageField(
      archive,
      displayJson,
      _kCustomBoard,
      _kActiveBoard,
      'custom_board',
    );
    await _packImageField(
      archive,
      displayJson,
      _kCustomWhite,
      _kActiveWhite,
      'custom_white_piece',
    );
    await _packImageField(
      archive,
      displayJson,
      _kCustomBlack,
      _kActiveBlack,
      'custom_black_piece',
    );
    await _packSingleField(archive, generalJson, _kBgMusic, 'background_music');
  }

  /// Pack a custom-image field.  If the "active" path points to the same
  /// file, its JSON value is updated to the archive-relative path as well.
  static Future<void> _packImageField(
    Archive archive,
    Map<String, dynamic> json,
    String customKey,
    String activeKey,
    String archiveName,
  ) async {
    final String? customPath = json[customKey] as String?;
    if (customPath == null ||
        customPath.isEmpty ||
        customPath.startsWith('assets/')) {
      return;
    }

    final File file = File(customPath);
    if (!file.existsSync()) {
      return;
    }

    final String ext = p.extension(customPath);
    final String archivePath = '$_mediaDir/$archiveName$ext';

    final Uint8List bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));

    // Update the "active" path first if it was pointing to the custom file.
    if (json[activeKey] == customPath) {
      json[activeKey] = archivePath;
    }
    json[customKey] = archivePath;
  }

  /// Pack a standalone media field (no paired active/custom keys).
  static Future<void> _packSingleField(
    Archive archive,
    Map<String, dynamic> json,
    String key,
    String archiveName,
  ) async {
    final String? filePath = json[key] as String?;
    if (filePath == null ||
        filePath.isEmpty ||
        filePath.startsWith('assets/')) {
      return;
    }

    final File file = File(filePath);
    if (!file.existsSync()) {
      return;
    }

    final String ext = p.extension(filePath);
    final String archivePath = '$_mediaDir/$archiveName$ext';

    final Uint8List bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
    json[key] = archivePath;
  }

  // ──────────────────── Media unpacking (import) ────────────────────

  /// Extract every bundled media file from the archive into local app
  /// storage and rewrite archive-relative paths in the JSON maps to the
  /// new absolute paths.  Returns the number of files extracted.
  static Future<int> _unpackMedia(
    Map<String, dynamic> data,
    Archive archive,
  ) async {
    final Directory appDir = (!kIsWeb && Platform.isAndroid)
        ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();

    final Directory imagesDir = Directory(p.join(appDir.path, 'images'));
    final Directory musicDir = Directory(p.join(appDir.path, 'music'));
    await imagesDir.create(recursive: true);
    await musicDir.create(recursive: true);

    final Map<String, ArchiveFile> archiveFiles = <String, ArchiveFile>{};
    for (final ArchiveFile f in archive) {
      if (f.isFile) {
        archiveFiles[f.name] = f;
      }
    }

    int count = 0;
    final String ts = DateTime.now().millisecondsSinceEpoch.toString();

    final Map<String, dynamic>? displayJson =
        data['displaySettings'] as Map<String, dynamic>?;
    final Map<String, dynamic>? generalJson =
        data['generalSettings'] as Map<String, dynamic>?;

    Future<bool> extractField(
      Map<String, dynamic> json,
      String key,
      Directory targetDir,
    ) async {
      final dynamic value = json[key];
      if (value is! String || !value.startsWith('$_mediaDir/')) {
        return false;
      }

      final ArchiveFile? af = archiveFiles[value];
      if (af == null) {
        return false;
      }

      final String ext = p.extension(value);
      final String baseName = p.basenameWithoutExtension(value);
      final String newPath = p.join(targetDir.path, '${baseName}_$ts$ext');

      await File(newPath).writeAsBytes(af.content as List<int>);

      // Replace every reference to this archive path within the same
      // JSON map (covers both "custom*" and the paired "active*" keys).
      final String archivePath = value;
      for (final String k in json.keys.toList()) {
        if (json[k] == archivePath) {
          json[k] = newPath;
        }
      }
      return true;
    }

    if (displayJson != null) {
      if (await extractField(displayJson, _kCustomBg, imagesDir)) {
        count++;
      }
      if (await extractField(displayJson, _kCustomBoard, imagesDir)) {
        count++;
      }
      if (await extractField(displayJson, _kCustomWhite, imagesDir)) {
        count++;
      }
      if (await extractField(displayJson, _kCustomBlack, imagesDir)) {
        count++;
      }
    }

    if (generalJson != null) {
      if (await extractField(generalJson, _kBgMusic, musicDir)) {
        count++;
      }
    }

    return count;
  }

  // ──────────────── JSON parsing & result assembly ──────────────────

  /// Parse [jsonStr] as a settings payload and optionally extract media.
  /// Pass [archive] when parsing from a ZIP bundle to unpack media files.
  static Future<ConfigImportResult> _importFromJsonString(
    String jsonStr, {
    Archive? archive,
  }) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return const ConfigImportResult(
        success: false,
        errorKind: ConfigImportErrorKind.invalidFile,
      );
    }

    if (data['formatVersion'] == null) {
      return const ConfigImportResult(
        success: false,
        errorKind: ConfigImportErrorKind.invalidFile,
      );
    }

    int mediaCount = 0;
    if (archive != null) {
      mediaCount = await _unpackMedia(data, archive);
    }

    _applySettings(data);

    logger.i('$_logTag Config imported ($mediaCount media files)');
    return ConfigImportResult(success: true, mediaCount: mediaCount);
  }

  // ─────────────────── Settings application ───────────────────

  static void _applySettings(Map<String, dynamic> data) {
    if (data['generalSettings'] is Map<String, dynamic>) {
      final Map<String, dynamic> json =
          data['generalSettings'] as Map<String, dynamic>;

      // Preserve device-local / sensitive values.
      // Keys are PascalCase due to field_rename: pascal in build.yaml.
      final GeneralSettings current = DB().generalSettings;
      json['IsPrivacyPolicyAccepted'] = current.isPrivacyPolicyAccepted;
      json['FirstRun'] = current.firstRun;
      json['LlmPromptHeader'] = '';
      json['LlmPromptFooter'] = '';
      json['LlmProvider'] = 'openai';
      json['LlmModel'] = '';
      json['LlmApiKey'] = '';
      json['LlmBaseUrl'] = '';
      json['LlmTemperature'] = 0.7;
      json['AiChatEnabled'] = false;
      json['LastPgnSaveDirectory'] ??= current.lastPgnSaveDirectory;

      DB().generalSettings = GeneralSettings.fromJson(json);
    }

    if (data['ruleSettings'] is Map<String, dynamic>) {
      DB().ruleSettings = RuleSettings.fromJson(
        data['ruleSettings'] as Map<String, dynamic>,
      );
    }

    if (data['displaySettings'] is Map<String, dynamic>) {
      DB().displaySettings = DisplaySettings.fromJson(
        data['displaySettings'] as Map<String, dynamic>,
      );
    }

    if (data['colorSettings'] is Map<String, dynamic>) {
      DB().colorSettings = ColorSettings.fromJson(
        data['colorSettings'] as Map<String, dynamic>,
      );
    }
  }

  static void _removeLlmFields(Map<String, dynamic> json) {
    for (final String key in <String>[
      'LlmPromptHeader',
      'LlmPromptFooter',
      'LlmProvider',
      'LlmModel',
      'LlmApiKey',
      'LlmBaseUrl',
      'LlmTemperature',
      'AiChatEnabled',
    ]) {
      json.remove(key);
    }
  }
}
