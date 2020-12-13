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

class Profile {
  static const defaultFileName = 'default-profile.json';
  static Profile _shared;

  File _file;
  Map<String, dynamic> _values = {};

  static shared() async {
    if (_shared == null) {
      _shared = Profile();
      await _shared._load(defaultFileName);
    }

    return _shared;
  }

  operator [](String key) => _values[key];

  operator []=(String key, dynamic value) => _values[key] = value;

  Future<bool> commit() async {
    _file.create(recursive: true);

    try {
      final contents = jsonEncode(_values);
      await _file.writeAsString(contents);
    } catch (e) {
      print('Error: $e');
      return false;
    }

    return true;
  }

  Future<bool> _load(String fileName) async {
    final docDir = await getApplicationDocumentsDirectory();
    _file = File('${docDir.path}/$fileName');

    try {
      final contents = await _file.readAsString();
      _values = jsonDecode(contents);
    } catch (e) {
      return false;
    }

    return true;
  }
}
