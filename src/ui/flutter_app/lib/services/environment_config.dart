// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

/// Environment configuration
///
/// Enables device to start the app with compile time options
class EnvironmentConfig {
  const EnvironmentConfig._();

  /// Gets whether we build for Monkey/Appium testing
  static const test = bool.fromEnvironment('test');

  /// Gets whether we build for devMode
  static const devMode = bool.fromEnvironment('dev_mode');

  /// Gets weather we build for a monkey test
  @Deprecated("Use EnvironmentConfig.test instead")
  static const monkeyTest = bool.fromEnvironment("monkey_test") || test;

  /// Gets whether we want catcher to be enabled
  /// Defaults to true
  static const catcher = bool.fromEnvironment("catcher", defaultValue: true);

  /// Gets weather we want catcher to be enabled
  /// Defaults to true
  static const logLevel = int.fromEnvironment("log_level", defaultValue: 4);
}
