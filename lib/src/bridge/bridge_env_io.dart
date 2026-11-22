import 'dart:io' show Platform;

/// 当前进程是否运行在 `flutter test` 单元测试环境中（基于 `FLUTTER_TEST` 环境变量判断）。
///
/// Whether the current process is running under `flutter test` (checked via the
/// `FLUTTER_TEST` environment variable).
bool get isFlutterTestEnvironment => Platform.environment.containsKey('FLUTTER_TEST');
