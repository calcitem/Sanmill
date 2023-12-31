// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../generated/assets/assets.gen.dart';
import '../generated/intl/l10n.dart';
import '../shared/themes/app_theme.dart';

class LicenseAgreementPage extends StatelessWidget {
  const LicenseAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(Assets.licenses.gpl30),
      builder: (BuildContext context, AsyncSnapshot<String> data) {
        late final String str;
        if (!data.hasData) {
          str = "Nothing to show";
        } else {
          str = data.data!;
        }

        return BlockSemantics(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              title: Text(
                S.of(context).license,
                style: AppTheme.appBarTheme.titleTextStyle,
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                str,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontFamily: "Monospace",
                    ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        );
      },
    );
  }
}
