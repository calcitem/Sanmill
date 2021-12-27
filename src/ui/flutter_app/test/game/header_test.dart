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

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n_en.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/services/storage/storage.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/storage_mock.dart';

void main() {
  testWidgets("GameHeader", (WidgetTester tester) async {
    const testString = "Test";

    DB.instance = MockedDB();
    const _screen = HeaderTip();

    await tester.pumpWidget(makeTestableWidget(_screen));

    expect(find.text(SEn().welcome), findsOneWidget);

    MillController().tip.showTip(testString);

    await tester.pump();

    expect(find.text(testString), findsOneWidget);
  });
}
