// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_commands_help_page.dart

import 'package:flutter/material.dart';

import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

/// Help page showing available voice commands
class VoiceCommandsHelpPage extends StatelessWidget {
  const VoiceCommandsHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final S loc = S.of(context);
    final bool isEnglish = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        leading: CustomDrawerIcon.of(context)?.drawerIcon,
        title: Text(loc.voiceCommandsHelp),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // Introduction
          Text(
            loc.voiceCommandsHelpIntro,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),

          // Game Control Commands
          _buildSectionHeader(context, loc.voiceCommandsGameControl),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsUndo,
            examples: isEnglish
                ? <String>['undo', 'back']
                : <String>['撤销', '取消'],
            description: loc.voiceCommandsUndoDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsRedo,
            examples: isEnglish ? <String>['redo', 'forward'] : <String>['重做'],
            description: loc.voiceCommandsRedoDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsRestart,
            examples: isEnglish
                ? <String>['restart', 'new game']
                : <String>['重新开始', '新游戏'],
            description: loc.voiceCommandsRestartDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsAiMove,
            examples: isEnglish
                ? <String>['ai move', 'computer move']
                : <String>['ai走', '电脑走'],
            description: loc.voiceCommandsAiMoveDesc,
          ),

          const SizedBox(height: 16),

          // Move Commands
          _buildSectionHeader(context, loc.voiceCommandsMoveControl),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsMovePiece,
            examples: isEnglish
                ? <String>['move a1 to b2', 'move a one to b two']
                : <String>['移动 a1 到 b2'],
            description: loc.voiceCommandsMovePieceDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsPlacePiece,
            examples: isEnglish
                ? <String>['place on a1', 'put on a one']
                : <String>['放置在 a1'],
            description: loc.voiceCommandsPlacePieceDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsRemovePiece,
            examples: isEnglish
                ? <String>['remove a1', 'take a one']
                : <String>['移除 a1'],
            description: loc.voiceCommandsRemovePieceDesc,
          ),

          const SizedBox(height: 16),

          // Settings Commands
          _buildSectionHeader(context, loc.voiceCommandsSettings),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsToggleSound,
            examples: isEnglish
                ? <String>['sound on', 'sound off', 'sound']
                : <String>['声音开启', '声音关闭', '音效'],
            description: loc.voiceCommandsToggleSoundDesc,
          ),
          _buildCommandCard(
            context,
            title: loc.voiceCommandsToggleVibration,
            examples: isEnglish
                ? <String>['vibration on', 'vibration off', 'vibrate']
                : <String>['震动开启', '震动关闭', '震动'],
            description: loc.voiceCommandsToggleVibrationDesc,
          ),

          const SizedBox(height: 24),

          // Tips
          _buildSectionHeader(context, loc.voiceCommandsTips),
          _buildTipCard(
            context,
            icon: Icons.volume_up,
            tip: loc.voiceCommandsTip1,
          ),
          _buildTipCard(context, icon: Icons.mic, tip: loc.voiceCommandsTip2),
          _buildTipCard(
            context,
            icon: Icons.language,
            tip: loc.voiceCommandsTip3,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCommandCard(
    BuildContext context, {
    required String title,
    required List<String> examples,
    required String description,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Text(
              S.of(context).examples,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: examples
                  .map(
                    (String example) => Chip(
                      label: Text(
                        '"$example"',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.blue[50],
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard(
    BuildContext context, {
    required IconData icon,
    required String tip,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(tip, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
