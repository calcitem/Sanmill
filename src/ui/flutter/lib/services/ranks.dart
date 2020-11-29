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

import 'dart:convert';
import 'dart:io';

class RankItem {
  //
  String name;
  int winCloudEngine, winAi;

  RankItem(Map<String, dynamic> values) {
    name = values['name'] ?? 'Anonymous';
    winCloudEngine = values['win_cloud_engine'] ?? 0;
    winAi = values['win_ai'] ?? 0;
  }

  RankItem.empty() {
    name = 'Anonymous';
    winCloudEngine = 0;
    winAi = 0;
  }

  RankItem.mock() {
    name = 'I am a hero';
    winCloudEngine = 3;
    winAi = 12;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'win_cloud_engine': winCloudEngine,
        'win_ai': winAi,
      };

  get score => winCloudEngine * 30 + winAi * 5;
}

class Ranks {
  //
  static const Host = 'api.calcitem.com';
  static const Port = 3838;
  static const QueryPath = '/ranks/';
  static const UploadPath = '/ranks/upload';

  static Future<List<RankItem>> load({pageIndex, int pageSize = 10}) async {
    //
    Uri url = Uri(
      scheme: 'http',
      host: Host,
      port: Port,
      path: QueryPath,
      queryParameters: {
        'page_index': '$pageIndex',
        'page_size': '$pageSize',
      },
    );

    final httpClient = HttpClient();

    try {
      final request = await httpClient.getUrl(url);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      final obj = jsonDecode(text);

      if (obj is! List) {
        print('Unexpected response: $text');
        return null;
      }

      final array = obj as List;
      final rankItems = List<RankItem>();

      array.forEach((row) => rankItems.add(RankItem(row)));

      return rankItems;
      //
    } catch (e) {
      print('Error: $e');
    } finally {
      httpClient.close();
    }

    return null;
  }

  static Future<bool> upload({String uuid, RankItem rank}) async {
    //
    Uri url = Uri(
        scheme: 'http',
        host: Host,
        port: Port,
        path: UploadPath,
        queryParameters: {
          'uuid': uuid,
          'name': rank.name,
          'win_cloud_engine': '${rank.winCloudEngine}',
          'win_ai': '${rank.winAi}',
        });

    final httpClient = HttpClient();

    try {
      final request = await httpClient.postUrl(url);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      print(text);
      return true;
      //
    } catch (e) {
      print('Error: $e');
    } finally {
      httpClient.close();
    }

    return false;
  }

  static Future<List<RankItem>> mockLoad({pageIndex, int pageSize = 10}) async {
    return [
      RankItem.mock(),
      RankItem.mock(),
      RankItem.mock(),
      RankItem.mock(),
      RankItem.mock(),
      RankItem.mock()
    ];
  }

  static Future<bool> mockUpload({String uuid, RankItem rank}) async {
    return true;
  }
}
