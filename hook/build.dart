import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const String _assetName = 'xue_hua_navite_video_player_objc_gen.dylib';
const String _pluginName = 'xue_hua_navite_video_player';
const List<String> _objCFlags = <String>['-x', 'objective-c', '-fobjc-arc'];

final Map<Architecture, String> _appleClangMacosTargetFlags = <Architecture, String>{
  Architecture.arm64: 'arm64-apple-darwin',
  Architecture.arm64e: 'arm64e-apple-darwin',
  Architecture.x64: 'x86_64-apple-darwin',
};

final Map<Architecture, Map<IOSSdk, String>> _appleClangIosTargetFlags =
    <Architecture, Map<IOSSdk, String>>{
      Architecture.arm64: <IOSSdk, String>{
        IOSSdk.iPhoneOS: 'arm64-apple-ios',
        IOSSdk.iPhoneSimulator: 'arm64-apple-ios-simulator',
      },
      Architecture.arm64e: <IOSSdk, String>{
        IOSSdk.iPhoneOS: 'arm64e-apple-ios',
        IOSSdk.iPhoneSimulator: 'arm64e-apple-ios-simulator',
      },
      Architecture.x64: <IOSSdk, String>{IOSSdk.iPhoneSimulator: 'x86_64-apple-ios-simulator'},
    };

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final CodeConfig codeConfig = input.config.code;
    final OS targetOS = codeConfig.targetOS;
    if (targetOS != OS.iOS && targetOS != OS.macOS) {
      return;
    }

    if (codeConfig.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError('LinkModePreference.static is not supported for $_assetName.');
    }

    final String platformDir = targetOS == OS.iOS ? 'ios' : 'macos';
    final Uri objcGenUri = input.packageRoot.resolve(
      '$platformDir/$_pluginName/Sources/${_pluginName}_objc_gen/',
    );
    final Directory objcGenDir = Directory.fromUri(objcGenUri);
    if (!objcGenDir.existsSync()) {
      throw StateError('Missing generated Objective-C directory: ${objcGenDir.path}');
    }

    final List<String> mFiles = <String>[];
    final List<String> hFiles = <String>[];
    for (final FileSystemEntity entity in objcGenDir.listSync(recursive: true)) {
      if (entity is File) {
        if (entity.path.endsWith('.m')) {
          mFiles.add(entity.path);
        } else if (entity.path.endsWith('.h')) {
          hFiles.add(entity.path);
        }
      }
    }
    mFiles.sort();
    hFiles.sort();

    if (mFiles.isEmpty) {
      throw StateError('No Objective-C (.m) files found in ${objcGenDir.path}');
    }

    final String compiler = _resolveCompiler(codeConfig);
    final String sysroot = _resolveSdkPath(codeConfig);
    final String targetTriple = _resolveTargetTriple(codeConfig);
    final String minOSFlag = _resolveMinOSFlag(codeConfig);
    final String includeDir = objcGenDir.path;

    final Uri objOutDir = input.outputDirectory.resolve('obj/');
    final Uri assetPath = input.outputDirectory.resolve(_assetName);
    final String rootPath = input.packageRoot.toFilePath();

    final List<String> compileFlags = <String>[
      '-isysroot',
      sysroot,
      '-target',
      targetTriple,
      minOSFlag,
      ..._objCFlags,
      '-fpic',
      '-gline-tables-only',
      '-I',
      includeDir,
    ];

    final List<String> objectFiles = await Future.wait<String>(<Future<String>>[
      for (final String src in mFiles)
        _compileObject(
          compiler: compiler,
          srcPath: src,
          rootPath: rootPath,
          objOutDir: objOutDir,
          compileFlags: compileFlags,
        ),
    ]);

    final List<String> linkArgs = <String>[
      '-shared',
      if (targetOS == OS.iOS) '-Wl,-encryptable',
      '-isysroot',
      sysroot,
      '-target',
      targetTriple,
      minOSFlag,
      '-framework',
      'Foundation',
      '-lobjc',
      ...objectFiles,
      '-o',
      assetPath.toFilePath(),
    ];
    await _runClang(compiler, linkArgs);

    output.dependencies.addAll(mFiles.map(Uri.file));
    output.dependencies.addAll(hFiles.map(Uri.file));

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        file: assetPath,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

String _resolveCompiler(CodeConfig codeConfig) {
  final String? compiler = codeConfig.cCompiler?.compiler.toFilePath();
  if (compiler != null && File(compiler).existsSync()) {
    return compiler;
  }
  return 'clang';
}

String _resolveSdkPath(CodeConfig codeConfig) {
  final String sdkName;
  if (codeConfig.targetOS == OS.iOS) {
    sdkName = codeConfig.iOS.targetSdk == IOSSdk.iPhoneOS ? 'iphoneos' : 'iphonesimulator';
  } else {
    sdkName = 'macosx';
  }
  final ProcessResult result = Process.runSync('xcrun', <String>[
    '--show-sdk-path',
    '--sdk',
    sdkName,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'xcrun',
      <String>['--show-sdk-path', '--sdk', sdkName],
      '${result.stderr}',
      result.exitCode,
    );
  }
  return (result.stdout as String)
      .split('\n')
      .map((String line) => line.trim())
      .firstWhere((String line) => line.isNotEmpty);
}

String _resolveTargetTriple(CodeConfig codeConfig) {
  final Architecture arch = codeConfig.targetArchitecture;
  if (codeConfig.targetOS == OS.iOS) {
    final IOSSdk targetSdk = codeConfig.iOS.targetSdk;
    final String? triple = _appleClangIosTargetFlags[arch]?[targetSdk];
    if (triple == null) {
      throw UnsupportedError('Unsupported iOS target: $arch ($targetSdk)');
    }
    return triple;
  }
  final String? triple = _appleClangMacosTargetFlags[arch];
  if (triple == null) {
    throw UnsupportedError('Unsupported macOS architecture: $arch');
  }
  return triple;
}

String _resolveMinOSFlag(CodeConfig codeConfig) {
  if (codeConfig.targetOS == OS.iOS) {
    final String version = _formatAppleVersion(codeConfig.iOS.deploymentVersion);
    if (codeConfig.iOS.targetSdk == IOSSdk.iPhoneOS) {
      return '-mios-version-min=$version';
    }
    return '-mios-simulator-version-min=$version';
  }
  final String version = _formatAppleVersion(codeConfig.macOS.deploymentVersion);
  return '-mmacosx-version-min=$version';
}

String _formatAppleVersion(AppleVersion version) {
  if (version.patch != 0) {
    return '${version.major}.${version.minor}.${version.patch}';
  }
  return '${version.major}.${version.minor}';
}

Future<String> _compileObject({
  required String compiler,
  required String srcPath,
  required String rootPath,
  required Uri objOutDir,
  required List<String> compileFlags,
}) async {
  final String relativePath = srcPath.startsWith(rootPath)
      ? srcPath.substring(rootPath.length)
      : File(srcPath).uri.pathSegments.last;
  final String objectPath = '${objOutDir.resolve(relativePath).toFilePath()}.o';
  File(objectPath).parent.createSync(recursive: true);

  await _runClang(compiler, <String>[...compileFlags, '-c', srcPath, '-o', objectPath]);
  return objectPath;
}

Future<void> _runClang(String compiler, List<String> args) async {
  final ProcessResult result = await Process.run(compiler, args);
  if (result.exitCode != 0) {
    final String out = '${result.stdout}\n${result.stderr}'.trim();
    throw ProcessException(compiler, args, out, result.exitCode);
  }
}
