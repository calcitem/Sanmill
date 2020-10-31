import '../mill/position.dart';

enum EngineType { Cloud, Native }

class EngineResponse {
  final String type;
  final dynamic value;
  EngineResponse(this.type, {this.value});
}

abstract class AiEngine {
  //
  Future<void> startup() async {}

  Future<void> shutdown() async {}

  Future<EngineResponse> search(Position position, {bool byUser = true});
}
