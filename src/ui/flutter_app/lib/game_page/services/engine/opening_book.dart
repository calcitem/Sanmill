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

part of '../mill.dart';

// This map contains FEN (Forsyth-Edwards Notation) strings mapped to their best moves
// specifically for the Nine Men's Morris game.
// Note: The second-to-last field in the FEN string, referred to as `rule50`,
// represents the half-move clock (a rule used in chess to track draws by the 50-move rule).
// In this context, the `rule50` field must always be set to 0.

Map<String, List<String>> nineMensMorrisFenToBestMoves = <String, List<String>>{
  "********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1": <String>[
    "d2",
    "b2"
  ],
  "********/****O***/******** b p p 1 8 0 9 0 0 0 0 0 0 0 0 1": <String>[
    "d6",
    "f6",
    "f4",
    "b2"
  ],
  "********/*****O**/******** b p p 1 8 0 9 0 0 0 0 0 0 0 0 1": <String>[
    "d6",
    "f6"
  ],
  "********/@***O***/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 2": <String>[
    "f4",
    "f6"
  ],
  "********/*@**O***/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 2": <String>[
    "b2",
    "f4",
    "b4"
  ],
  "********/**@*O***/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 2": <String>["d6"],
  "********/****O@**/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 2": <String>["f6"],
  "********/@****O**/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 2": <String>["f6"],
  "********/@*O*O***/******** b p p 2 7 1 8 0 0 0 0 0 0 0 0 2": <String>[
    "b4",
    "f2",
    "b2",
    "f6"
  ],
  "********/*@O*O***/******** b p p 2 7 1 8 0 0 0 0 0 0 0 0 2": <String>["b2"],
  "********/*@**O*O*/******** b p p 2 7 1 8 0 0 0 0 0 0 0 0 2": <String>["b2"],
  "********/O*@*O***/******** b p p 2 7 1 8 0 0 0 0 0 0 0 0 2": <String>["b4"],
  "********/@O***O**/******** b p p 2 7 1 8 0 0 0 0 0 0 0 0 2": <String>[
    "b4",
    "f4"
  ],
  "********/@*O*O*@*/******** w p p 2 7 2 7 0 0 0 0 0 0 0 0 3": <String>[
    "f2",
    "d5",
    "b6"
  ],
  "********/@*OOO*@*/******** b p p 3 6 2 7 0 0 0 0 0 0 0 0 3": <String>["f6"],
  "O*******/@*O*O*@*/******** b p p 3 6 2 7 0 0 0 0 0 0 0 0 3": <String>["b6"],
  "********/@@OOO*@*/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 4": <String>[
    "b2",
    "b6"
  ],
  "********/@@OOOO@*/******** w p r 4 5 3 5 1 0 0 0 0 0 15762598695796736 0 4":
      <String>["xf6"],
  "********/@*OOOO@*/******** b p p 4 5 2 6 0 0 0 0 0 0": <String>["f6"],
  "********/@@OOO*@O/******** b p p 4 5 3 6 0 0 0 0 0 0 0 0 4": <String>["b2"],
  "O*******/@*O*O*@@/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 4": <String>["b2"],
  "O*******/@*O*OO@@/******** b p p 4 5 3 6 0 0 0 0 0 0 0 0 4": <String>[
    "f2",
    "f6"
  ],
  "O*******/@@O*OO@@/******** b p r 4 4 4 5 0 1 0 0 0 0 8585216 0 4": <String>[
    "xb2"
  ],
  "********/@@OOOO@*/******** w p p 4 5 3 5 0 0 0 0 0 0 15762598695796736 0 5":
      <String>["b6"],
  "O*******/@*O@OO@@/******** w p p 4 5 4 5 0 0 0 0 0 0 0 0 5": <String>["f6"],
  "O*******/@@O*O*@@/******** w p p 3 5 4 5 0 0 0 0 0 0 8585216 0 5": <String>[
    "b2"
  ],
  "O*******/@@O*OO@@/******** b p p 4 4 4 5 0 0 0 0 0 0 8585216 0 5": <String>[
    "f2"
  ],
};
