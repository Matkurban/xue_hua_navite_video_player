import 'dart:io';

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

  _syncAppleObjcGen();

  if (exitCode != 0) {
    exit(exitCode);
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
