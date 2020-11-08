/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

class AnalysisItem {
  //
  String move, stepName;
  int score;
  double winrate;

  AnalysisItem({this.move, this.score, this.winrate});

  @override
  String toString() {
    return '{move: ${stepName ?? move}, score: $score, winrate: $winrate}';
  }
}

class AnalysisFetcher {
  //
  static List<AnalysisItem> fetch(String response, {limit = 5}) {
    //
    final segments = response.split('|');

    List<AnalysisItem> result = [];

    final regx = RegExp(r'move:(.{4}).+score:(\-?\d+).+winrate:(\d+.?\d*)');

    for (var segment in segments) {
      //
      final match = regx.firstMatch(segment);

      if (match == null) break;

      final move = match.group(1);
      final score = int.parse(match.group(2));
      final winrate = double.parse(match.group(3));

      result.add(AnalysisItem(move: move, score: score, winrate: winrate));
      if (result.length == limit) break;
    }

    return result;
  }
}
