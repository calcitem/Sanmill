// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_scenarios.dart

/// Contains a list of test scenarios and steps for data-driven testing.
/// Each scenario includes a 'description' and a list of 'steps'.
final List<Map<String, dynamic>> testScenarios = <Map<String, dynamic>>[
  <String, dynamic>{
    'description': 'Start a new game and play a few moves',
    'steps': <Map<String, String>>[
      <String, String>{
        'action': 'tap',
        'key': 'custom_drawer_drawer_overlay_button',
        'expect': 'Drawer button should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'drawer_item_general_settings',
        'expect': 'General Settings item should be present',
      },
      <String, String>{
        'action': 'verify',
        'key': 'general_settings_page_settings_list',
        'expect': 'General Settings page should be displayed',
      },
      <String, String>{
        'action': 'scrollUntilVisible',
        'scrollable': 'settings_list',
        'key': 'general_settings_page_settings_card_restore_default_settings',
        'scrollIncrement': '1000',
        'resetScroll': 'true',
        'expect': 'The target item should be scrollable into view',
      },
      <String, String>{
        'action': 'tap',
        'key': 'general_settings_page_settings_card_restore_default_settings',
        'expect': 'Should tap the target item once visible',
      },
      <String, String>{
        'action': 'verify',
        'key': 'reset_settings_alert_dialog_ok_button',
        'expect': 'Reset Settings Alert Dialog should be displayed',
      },
      <String, String>{
        'action': 'tap',
        'key': 'reset_settings_alert_dialog_ok_button',
        'expect': 'Should tap the OK button',
      },
      <String, String>{
        'action': 'customFunction',
        'functionName': 'setSkillLevelAndMovingTime',
        'expect': 'Should set the skill level and moving time',
      },
      <String, String>{
        'action': 'scrollUntilVisible',
        'scrollable': 'settings_list',
        'key': 'general_settings_page_settings_card_difficulty_skill_level',
        'resetScroll': 'true',
        'expect': 'The target item should be scrollable into view',
      },
      <String, String>{
        'action': 'tap',
        'key': 'general_settings_page_settings_card_difficulty_skill_level',
        'expect': 'Should tap the target item once visible',
      },
      <String, String>{
        'action': 'tap',
        'key': 'skill_level_picker_confirm_button',
        'expect': 'Should tap the confirm button',
      },
      <String, String>{
        'action': 'scrollUntilVisible',
        'scrollable': 'settings_list',
        'key':
            'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
        'resetScroll': 'true',
        'expect': 'The target item should be scrollable into view',
      },
      <String, String>{
        'action': 'verify',
        'key':
            'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
        'expect': 'Shuffling Enabled switch should be present',
      },
      <String, String>{
        'action': 'tap',
        'key':
            'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
        'expect': 'Should tap the target item once visible',
      },
      <String, String>{
        'action': 'tap',
        'key': 'custom_drawer_drawer_overlay_button',
        'expect': 'Drawer button should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'drawer_item_rule_settings',
        'expect': 'Rule Settings item should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'rule_settings_tile_rule_set',
        'expect': 'Rule Set tile should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'radio_nine_mens_morris',
        'expect': "Should tap the Nine Men's Morris radio button",
      },
      <String, String>{
        'action': 'tap',
        'key': 'custom_drawer_drawer_overlay_button',
        'expect': 'Drawer button should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'drawer_item_appearance',
        'expect': 'Appearance Settings item should be present',
      },
      <String, String>{
        'action': 'tap',
        'key':
            'display_settings_card_history_navigation_toolbar_shown_switch_tile',
        'expect': 'History Navigation Toolbar Shown switch should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'display_settings_card_notations_shown_switch_tile',
        'expect': 'Notations Shown switch should be present',
      },
      <String, String>{
        'action': 'tap',
        'key':
            'display_settings_card_unplaced_removed_pieces_shown_switch_tile',
        'expect': 'Unplaced/Removed Pieces Shown switch should be present',
      },
      <String, String>{
        'action': 'tap',
        'key':
            'display_settings_card_positional_advantage_indicator_shown_switch_tile',
        'expect':
            'Positional Advantage Indicator Shown switch should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'display_settings_card_advantage_graph_shown_switch_tile',
        'expect': 'Advantage Graph Shown switch should be present',
      },
      <String, String>{
        'action': 'delay',
        'duration': '4000', // Delay for 4000 milliseconds (4 seconds)
      },
      <String, String>{
        'action': 'tap',
        'key': 'custom_drawer_drawer_overlay_button',
        'expect': 'Drawer button should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'drawer_item_ai_vs_ai',
        'expect': 'AI vs AI item should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'play_area_toolbar_item_game',
        'expect': 'Game toolbar item should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'new_game_option',
        'expect': 'New Game toolbar item should be present',
      },
      <String, String>{
        'action': 'tap',
        'key': 'restart_game_yes_button',
        'expect': 'Should tap the Yes button',
      },
    ],
  },
  // Add more scenarios here...
];
