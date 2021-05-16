/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Settings {
  static const settingsFileName = 'sanmill_settings.json';
  static Settings? _instance;

  late File _file;
  Map<String, dynamic>? _values = {};

  static instance() async {
    if (_instance == null) {
      _instance = Settings();
      await _instance!._load(settingsFileName);
      print("defaultFileName: $settingsFileName");
    }

    return _instance;
  }

  operator [](String key) => _values![key];

  operator []=(String key, dynamic value) => _values![key] = value;

  Future<bool> commit() async {
    _file.create(recursive: true);

    final contents = jsonEncode(_values);
    await _file.writeAsString(contents);

    //print("Settings is committed.");

    return true;
  }

  Future<bool> _load(String fileName) async {
    late var docDir;

    if (Platform.isAndroid) {
      docDir = await getExternalStorageDirectory();
      _file = File('${docDir.path}/$fileName');
    } else if (Platform.isWindows) {
      _file = File('$fileName');
    } else {
      docDir = await getApplicationDocumentsDirectory();
      _file = File('${docDir.path}/$fileName');
    }

    print("Loading $_file ...");

    try {
      final contents = await _file.readAsString();
      _values = jsonDecode(contents);
      print(_values);
    } catch (e) {
      print(e);
      return false;
    }

    return true;
  }

  Future<void> restore() async {
    print("Restoring Settings...");

    if (_file.existsSync()) {
      _file.deleteSync();
      print("$_file deleted");
    } else {
      print("$_file does not exist");
    }
  }
}
