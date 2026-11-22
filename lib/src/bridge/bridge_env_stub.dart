/// 当前进程是否运行在 `flutter test` 单元测试环境中（非 IO 平台默认返回 `false`）。
///
/// Whether the current process is running under `flutter test` (always `false`
/// on non-IO platforms such as Web).
bool get isFlutterTestEnvironment => false;
