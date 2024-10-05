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

import 'package:flutter_gemma/flutter_gemma.dart';

class LLM {
  factory LLM() {
    return _instance;
  }

  LLM._internal() : _gemma = Gemma.instance;
  static final LLM _instance = LLM._internal();
  final Gemma _gemma;

  static Future<void> initialize({int maxTokens = 32}) async {
    await Gemma.instance.init(maxTokens: maxTokens);
  }

  Future<String?> generateResponse(String prompt) async {
    return _gemma.getResponse(prompt: prompt);
  }

  Stream<String?> generateResponseAsStream(String prompt) {
    return _gemma.getResponseAsync(prompt: prompt);
  }
}
