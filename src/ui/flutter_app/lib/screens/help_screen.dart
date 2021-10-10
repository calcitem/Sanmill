import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.0,
        backgroundColor: Color(Config.darkBackgroundColor),
        centerTitle: true,
        title: Text(
          S.of(context).howToPlay,
          style: TextStyle(
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
