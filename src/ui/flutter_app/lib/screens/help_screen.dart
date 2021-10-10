import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          S.of(context).howToPlay,
          style: TextStyle(
            fontSize: Config.fontSize + 4,
            fontWeight: FontWeight.bold,
            color: AppTheme.helpTextColor,
          ),
        ),
      ),
      backgroundColor: Color(Config.darkBackgroundColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          S.of(context).helpContent,
          style: TextStyle(
            fontSize: Config.fontSize,
            color: AppTheme.helpTextColor,
          ),
        ),
      ),
    );
  }
}
