// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_spacer.dart

import 'package:flutter/material.dart';

import '../themes/app_theme.dart';

class CustomSpacer extends StatelessWidget {
  const CustomSpacer({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: AppTheme.sizedBoxHeight);
}
