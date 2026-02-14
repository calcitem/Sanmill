// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// custom_drawer_value_test.dart
//
// Tests for CustomDrawerValue state class.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  setUp(() {
    DB.instance = MockDB();
  });

  group('CustomDrawerValue', () {
    test('default constructor should have drawer hidden', () {
      const CustomDrawerValue value = CustomDrawerValue();
      expect(value.isDrawerVisible, isFalse);
    });

    test('constructor with isDrawerVisible=true', () {
      const CustomDrawerValue value = CustomDrawerValue(isDrawerVisible: true);
      expect(value.isDrawerVisible, isTrue);
    });

    test('factory hidden should create hidden state', () {
      final CustomDrawerValue value = CustomDrawerValue.hidden();
      expect(value.isDrawerVisible, isFalse);
    });

    test('factory visible should create visible state', () {
      final CustomDrawerValue value = CustomDrawerValue.visible();
      expect(value.isDrawerVisible, isTrue);
    });

    test('hidden and visible should be different states', () {
      final CustomDrawerValue hidden = CustomDrawerValue.hidden();
      final CustomDrawerValue visible = CustomDrawerValue.visible();

      expect(hidden.isDrawerVisible, isNot(visible.isDrawerVisible));
    });
  });
}
