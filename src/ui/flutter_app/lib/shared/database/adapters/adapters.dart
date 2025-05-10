// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// adapters.dart

/// Although marked as a library this package is tightly integrated into the app

library;

import 'dart:convert' as convert;

import 'package:flutter/material.dart' show Locale, Color;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart' show JsonSerializable;

import '../../../statistics/model/stats_settings.dart';

part 'color_adapter.dart';
part 'locale_adapter.dart';
part 'stats_adapter.dart';
