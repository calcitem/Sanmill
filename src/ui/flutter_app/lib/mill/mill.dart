/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/// Although marked as a library this package is tightly integrated into the app
library mill;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/array_helper.dart';

part 'src/controller.dart';
part 'src/game.dart';
part 'src/mills.dart';
part 'src/position.dart';
part 'src/recorder.dart';
part 'src/types.dart';
part 'src/zobrist.dart';
