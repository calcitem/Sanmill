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
