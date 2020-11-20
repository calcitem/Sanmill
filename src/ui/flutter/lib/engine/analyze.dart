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

class AnalyzeItem {
  String move, moveName;
  int score;
  double winRate;

  AnalyzeItem({this.move, this.score, this.winRate});

  @override
  String toString() {
    return '{move: ${moveName ?? move}, score: $score, winRate: $winRate}';
  }
}

class AnalyzeFetcher {
  static List<AnalyzeItem> fetch(String response, {limit = 5}) {
    final segments = response.split('|');

    List<AnalyzeItem> result = [];

    final regExp = RegExp(r'move:(.{4}).+score:(\-?\d+).+winRate:(\d+.?\d*)');

    for (var segment in segments) {
      final match = regExp.firstMatch(segment);

      if (match == null) break;

      final move = match.group(1);
      final score = int.parse(match.group(2));
      final winRate = double.parse(match.group(3));

      result.add(AnalyzeItem(move: move, score: score, winRate: winRate));
      if (result.length == limit) break;
    }

    return result;
  }
}
