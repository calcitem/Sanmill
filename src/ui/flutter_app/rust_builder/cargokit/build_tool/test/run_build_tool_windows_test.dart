// SPDX-License-Identifier: AGPL-3.0-or-later

@TestOn('windows')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory fixtureRoot;
  late String fakeDartExecutable;
  late Directory sandbox;
  late String wrapperPath;

  setUpAll(() async {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'sanmill_cargokit_exit_fixture_',
    );
    final String sourcePath = path.join(fixtureRoot.path, 'fake_dart.dart');
    fakeDartExecutable = path.join(fixtureRoot.path, 'fake_dart.exe');
    File(sourcePath).writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  if (Platform.environment['FAKE_DART_MODE'] == 'always_fail') {
    exit(37);
  }
  if (args.isNotEmpty && (args.first == 'pub' || args.first == 'compile')) {
    exit(0);
  }
  final File marker = File(Platform.environment['FAKE_DART_RETRY_MARKER']!);
  if (marker.existsSync()) {
    exit(19);
  }
  marker.createSync(recursive: true);
  exit(253);
}
''');
    final ProcessResult compileResult = await Process.run(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', sourcePath, '-o', fakeDartExecutable],
    );
    expect(compileResult.exitCode, 0, reason: compileResult.stderr.toString());
  });

  tearDownAll(() {
    fixtureRoot.deleteSync(recursive: true);
  });

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync(
      'sanmill_cargokit_exit_test_',
    );
    wrapperPath = path.normalize(
      path.join(Directory.current.path, '..', 'run_build_tool.cmd'),
    );
    final String dartExecutablePath = path.join(
      sandbox.path,
      'flutter',
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      'dart.exe',
    );
    File(dartExecutablePath).createSync(recursive: true);
    File(fakeDartExecutable).copySync(dartExecutablePath);
  });

  tearDown(() {
    sandbox.deleteSync(recursive: true);
  });

  test('propagates a Dart failure to Gradle', () async {
    final ProcessResult result = await _runWrapper(
      wrapperPath: wrapperPath,
      sandbox: sandbox,
      extraEnvironment: const <String, String>{
        'FAKE_DART_MODE': 'always_fail',
      },
    );

    expect(result.exitCode, 37, reason: result.stderr.toString());
  });

  test('propagates the retry result after an invalid snapshot', () async {
    final String markerPath = path.join(sandbox.path, 'retried.marker');

    final ProcessResult result = await _runWrapper(
      wrapperPath: wrapperPath,
      sandbox: sandbox,
      extraEnvironment: <String, String>{
        'FAKE_DART_RETRY_MARKER': markerPath,
      },
    );

    expect(File(markerPath).existsSync(), isTrue);
    expect(result.exitCode, 19, reason: result.stderr.toString());
  });
}

Future<ProcessResult> _runWrapper({
  required String wrapperPath,
  required Directory sandbox,
  Map<String, String> extraEnvironment = const <String, String>{},
}) {
  final String flutterRoot = path.join(sandbox.path, 'flutter');
  final String toolTemp = path.join(sandbox.path, 'tool_temp');
  return Process.run(
    'cmd.exe',
    <String>['/d', '/c', wrapperPath, 'build-gradle'],
    environment: <String, String>{
      ...Platform.environment,
      'FLUTTER_ROOT': flutterRoot,
      'CARGOKIT_TOOL_TEMP_DIR': toolTemp,
      ...extraEnvironment,
    },
  );
}
