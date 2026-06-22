// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../../../shared/services/logger.dart';
import 'opening_book_models.dart';
import 'opening_book_repository.dart';
import 'opening_book_source_models.dart';

class OpeningBookStudioRepository {
  const OpeningBookStudioRepository({
    this.curatedSourcePath = 'tool/nmm_curated_openings.json',
  });

  static const String fileExtension = 'json';
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');
  static const String _logTag = '[opening_book_studio]';

  final String curatedSourcePath;

  Future<SanmillOpeningBookSourcePackage> loadNmmSource() async {
    if (!kIsWeb) {
      final File file = File(curatedSourcePath);
      if (file.existsSync()) {
        return parseSourcePackage(await file.readAsString());
      }
    }

    await OpeningBookRepository.instance.ensureLoaded();
    return SanmillOpeningBookSourcePackage.fromOpeningEntries(
      OpeningBookRepository.instance.openingsFor(isElFilja: false),
    );
  }

  Future<void> saveNmmSource(SanmillOpeningBookSourcePackage package) async {
    assert(
      package.variant == 'nmm',
      'Opening Book Studio can only save NMM source packages.',
    );
    if (kIsWeb) {
      throw const FileSystemException(
        'Opening book source assets cannot be saved on Web.',
      );
    }
    final File file = File(curatedSourcePath);
    file.parent.createSync(recursive: true);
    await file.writeAsString('${encodeSourcePackage(package)}\n', flush: true);
    logger.i('$_logTag Saved source package to ${file.path}');
  }

  Future<bool?> exportSourcePackage(
    SanmillOpeningBookSourcePackage package, {
    required String dialogTitle,
  }) async {
    if (kIsWeb) {
      return false;
    }
    final String defaultFileName =
        '${package.book.id}_${DateTime.now().millisecondsSinceEpoch}.sbook.json';
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: const <String>[fileExtension],
    );
    if (outputPath == null) {
      return null;
    }

    final String path = outputPath.toLowerCase().endsWith('.json')
        ? outputPath
        : '$outputPath.json';
    await File(path).writeAsString('${encodeSourcePackage(package)}\n');
    logger.i('$_logTag Exported source package to $path');
    return true;
  }

  Future<SanmillOpeningBookSourcePackage?> importSourcePackage() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[fileExtension],
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }
    return importSourcePackageFromPath(result.files.single.path!);
  }

  Future<SanmillOpeningBookSourcePackage> importSourcePackageFromPath(
    String path,
  ) async {
    final File file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Opening book file not found', path);
    }
    return parseSourcePackage(await file.readAsString());
  }

  Future<void> writeSourcePackageToPath(
    SanmillOpeningBookSourcePackage package,
    String path,
  ) async {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    await file.writeAsString('${encodeSourcePackage(package)}\n');
  }

  SanmillOpeningBookSourcePackage parseSourcePackage(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is List) {
      final List<OpeningEntry> entries = decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> raw) =>
                OpeningEntry.fromJson(Map<String, dynamic>.from(raw)),
          )
          .toList(growable: false);
      return SanmillOpeningBookSourcePackage.fromOpeningEntries(entries);
    }
    if (decoded is Map) {
      final SanmillOpeningBookSourcePackage package =
          SanmillOpeningBookSourcePackage.fromJson(
            Map<String, dynamic>.from(decoded),
          );
      final OpeningBookSourceValidationResult validation =
          validateSanmillOpeningBookSource(package);
      if (!validation.isValid) {
        throw FormatException(validation.errors.join('\n'));
      }
      return package;
    }
    throw const FormatException('Opening book source must be a JSON object.');
  }

  String encodeSourcePackage(SanmillOpeningBookSourcePackage package) {
    return _encoder.convert(package.toJson());
  }

  String displayPath(String path) => p.normalize(path);
}
