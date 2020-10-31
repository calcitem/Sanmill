import 'dart:convert';
import 'dart:io';

class RankItem {
  //
  String name;
  int winCloudEngine, winPhoneAi;

  RankItem(Map<String, dynamic> values) {
    name = values['name'] ?? '无名英雄';
    winCloudEngine = values['win_cloud_engine'] ?? 0;
    winPhoneAi = values['win_phone_ai'] ?? 0;
  }

  RankItem.empty() {
    name = '无名英雄';
    winCloudEngine = 0;
    winPhoneAi = 0;
  }

  RankItem.mock() {
    name = '我是英雄';
    winCloudEngine = 3;
    winPhoneAi = 12;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'win_cloud_engine': winCloudEngine,
        'win_phone_ai': winPhoneAi,
      };

  get score => winCloudEngine * 30 + winPhoneAi * 5;
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
    Uri url = Uri(scheme: 'http', host: Host, port: Port, path: UploadPath, queryParameters: {
      'uuid': uuid,
      'name': rank.name,
      'win_cloud_engine': '${rank.winCloudEngine}',
      'win_phone_ai': '${rank.winPhoneAi}',
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
    return [RankItem.mock(), RankItem.mock(), RankItem.mock(), RankItem.mock(), RankItem.mock(), RankItem.mock()];
  }

  static Future<bool> mockUpload({String uuid, RankItem rank}) async {
    return true;
  }
}
