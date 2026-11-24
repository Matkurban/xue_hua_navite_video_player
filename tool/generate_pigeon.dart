import 'dart:io';

const String _objcGenAssetId =
    'package:xue_hua_navite_video_player/xue_hua_navite_video_player_objc_gen.dylib';
const String _ffigenConfigPath = 'tool/pigeon/player_api_ffigen_config.dart';
const String _ffiDartOutPath = 'lib/src/pigeon/player_api.g.ffi.dart';

Future<void> main(List<String> args) async {
  final env = Map<String, String>.from(Platform.environment);
  final androidSdk = _resolveAndroidHome(env);
  if (androidSdk != null && androidSdk.isNotEmpty) {
    env.putIfAbsent('ANDROID_HOME', () => androidSdk);
    env.putIfAbsent('ANDROID_SDK_ROOT', () => androidSdk);
  }

  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', 'pigeon', '--input', 'pigeons/player_api.dart', ...args],
    environment: env,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;

  if (exitCode != 0) {
    _syncAppleObjcGen();
    exit(exitCode);
  }

  _injectFfigenAssetId();
  if (Platform.isMacOS) {
    final ffigenProcess = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', _ffigenConfigPath],
      environment: env,
      mode: ProcessStartMode.inheritStdio,
    );
    final ffigenExitCode = await ffigenProcess.exitCode;
    if (ffigenExitCode != 0) {
      _syncAppleObjcGen();
      exit(ffigenExitCode);
    }
    _verifyFfiDefaultAsset();
  }

  _syncAppleObjcGen();

  final orientationProcess = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', 'pigeon', '--input', 'pigeons/orientation_api.dart', ...args],
    environment: env,
    mode: ProcessStartMode.inheritStdio,
  );
  final orientationExitCode = await orientationProcess.exitCode;
  if (orientationExitCode != 0) {
    exit(orientationExitCode);
  }
}

void _injectFfigenAssetId() {
  final configFile = File(_ffigenConfigPath);
  if (!configFile.existsSync()) {
    throw StateError('Missing ffigen config file: $_ffigenConfigPath');
  }

  final content = configFile.readAsStringSync();
  const assetIdLine = "      assetId: '$_objcGenAssetId',";
  if (content.contains("assetId: '$_objcGenAssetId'")) {
    return;
  }

  const anchor = "      module: 'xue_hua_navite_video_player',";
  if (!content.contains(anchor)) {
    throw StateError('Could not find Output module anchor in $_ffigenConfigPath');
  }

  configFile.writeAsStringSync(content.replaceFirst(anchor, '$anchor\n$assetIdLine'));
}

void _verifyFfiDefaultAsset() {
  final ffiDartFile = File(_ffiDartOutPath);
  if (!ffiDartFile.existsSync()) {
    throw StateError('Missing generated FFI Dart file: $_ffiDartOutPath');
  }

  final content = ffiDartFile.readAsStringSync();
  final pattern = RegExp(
    "@ffi\\.DefaultAsset\\(\\s*'${RegExp.escape(_objcGenAssetId)}',?\\s*\\)\\r?\\nlibrary;",
  );
  if (!pattern.hasMatch(content)) {
    throw StateError(
      'Generated $_ffiDartOutPath is missing @ffi.DefaultAsset(\'$_objcGenAssetId\') library;',
    );
  }
}

String? _resolveAndroidHome(Map<String, String> env) {
  final fromEnv = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty && Directory(fromEnv).existsSync()) {
    return fromEnv;
  }

  final localProps = File('example/android/local.properties');
  if (localProps.existsSync()) {
    for (final line in localProps.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.startsWith('sdk.dir=')) {
        final raw = trimmed.substring('sdk.dir='.length).trim();
        final unescaped = raw.replaceAll(r'\:', ':').replaceAll(r'\\', r'\');
        if (unescaped.isNotEmpty && Directory(unescaped).existsSync()) {
          return unescaped;
        }
      }
    }
  }

  final home = env['HOME'];
  if (home != null) {
    final defaultMacSdk = '$home/Library/Android/sdk';
    if (Directory(defaultMacSdk).existsSync()) {
      return defaultMacSdk;
    }
  }
  return null;
}

void _syncAppleObjcGen() {
  final iosGenDir = Directory(
    'ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player_objc_gen',
  );
  if (!iosGenDir.existsSync()) {
    return;
  }

  final macosGenDir = Directory(
    'macos/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player_objc_gen',
  );
  macosGenDir.createSync(recursive: true);

  for (final entity in iosGenDir.listSync()) {
    if (entity is File && entity.path.endsWith('.o')) {
      entity.deleteSync();
    }
  }

  final validNames = <String>{};
  for (final entity in iosGenDir.listSync()) {
    if (entity is File && (entity.path.endsWith('.h') || entity.path.endsWith('.m'))) {
      final name = entity.uri.pathSegments.last;
      validNames.add(name);
      entity.copySync('${macosGenDir.path}/$name');
    }
  }

  for (final entity in macosGenDir.listSync()) {
    if (entity is File) {
      final name = entity.uri.pathSegments.last;
      if (!validNames.contains(name)) {
        entity.deleteSync();
      }
    }
  }
}
