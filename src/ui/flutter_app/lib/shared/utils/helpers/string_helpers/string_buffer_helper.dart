// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// string_buffer_helper.dart

import '../../../database/database.dart';

/// StringBuffer Extension
///
/// Extends the StringBuffer Object with some convenience methods used through the app.
extension CustomStringBuffer on StringBuffer {
  void writeComma([Object? content = ""]) =>
      writeln(DB().generalSettings.screenReaderSupport ? "$content," : content);

  void writePeriod([Object? content = ""]) =>
      writeln(DB().generalSettings.screenReaderSupport ? "$content." : content);

  void writeSpace([Object? content = ""]) => write("$content ");

  /// Writes the given number to the buffer.
  /// It will add an extra space in front of single digit numbers but wont fix three digit cases.
  void writeNumber(int number) => write(number < 10 ? " $number." : "$number.");
}
