import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.0,
        backgroundColor: LocalDatabaseService.colorSettings.darkBackgroundColor,
        centerTitle: true,
        title: Text(
          S.of(context).howToPlay,
          style: TextStyle(
            color: AppTheme.helpTextColor,
          ),
        ),
      ),
      backgroundColor: LocalDatabaseService.colorSettings.darkBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          S.of(context).helpContent,
          style: TextStyle(
            fontSize: LocalDatabaseService.display.fontSize,
            color: AppTheme.helpTextColor,
          ),
        ),
      ),
    );
  }
}
