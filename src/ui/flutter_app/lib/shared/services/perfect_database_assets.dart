// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_database_assets.dart

const String perfectDatabaseAssetDirectory = 'assets/databases';

const List<String> standardPerfectDatabaseFileNames = <String>[
  'std.secval',
  'std_0_0_9_9.sec2',
  'std_0_1_9_8.sec2',
  'std_1_1_8_8.sec2',
  'std_1_2_8_7.sec2',
  'std_1_3_7_6.sec2',
  'std_2_2_7_7.sec2',
  'std_2_3_6_6.sec2',
  'std_2_3_7_6.sec2',
  'std_2_4_6_5.sec2',
  'std_3_3_0_0.sec2',
  'std_3_3_5_5.sec2',
  'std_3_3_6_5.sec2',
  'std_3_3_6_6.sec2',
  'std_3_4_0_0.sec2',
  'std_3_4_5_5.sec2',
  'std_3_4_6_5.sec2',
  'std_4_3_0_0.sec2',
  'std_4_3_5_5.sec2',
  'std_4_4_5_5.sec2',
];

const List<String> morabarabaPerfectDatabaseFileNames = <String>[
  'mora.secval',
  'mora_0_0_12_12.sec2',
  'mora_0_1_12_11.sec2',
  'mora_1_1_11_11.sec2',
  'mora_1_2_11_10.sec2',
  'mora_1_3_10_9.sec2',
  'mora_2_2_10_10.sec2',
];

const List<String> laskerPerfectDatabaseFileNames = <String>[
  'lask.secval',
  'lask_0_0_10_10.sec2',
  'lask_0_1_10_9.sec2',
  'lask_1_1_9_9.sec2',
  'lask_1_2_9_8.sec2',
];

const List<String> bundledPerfectDatabaseFileNames = <String>[
  ...standardPerfectDatabaseFileNames,
  ...laskerPerfectDatabaseFileNames,
  ...morabarabaPerfectDatabaseFileNames,
];

String perfectDatabaseAssetPath(String fileName) {
  assert(!fileName.contains('/'), 'database asset names must be file names');
  return '$perfectDatabaseAssetDirectory/$fileName';
}
