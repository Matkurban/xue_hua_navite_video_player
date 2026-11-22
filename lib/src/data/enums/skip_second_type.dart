/// 快进 / 快退的单次步进时长预设枚举。
///
/// Preset step duration enumeration for seek-forward and seek-backward actions.
enum SkipSecondType {
  /// 单次步进 5 秒。
  ///
  /// Step by 5 seconds.
  second5(value: 5),

  /// 单次步进 10 秒（默认）。
  ///
  /// Step by 10 seconds (default).
  second10(value: 10),

  /// 单次步进 15 秒。
  ///
  /// Step by 15 seconds.
  second15(value: 15),

  /// 单次步进 30 秒。
  ///
  /// Step by 30 seconds.
  second30(value: 30),

  /// 单次步进 45 秒。
  ///
  /// Step by 45 seconds.
  second45(value: 45),

  /// 单次步进 60 秒。
  ///
  /// Step by 60 seconds.
  second60(value: 60);

  /// 步进秒数（整数）。
  ///
  /// Step length in whole seconds.
  final int value;

  /// 创建步进时长枚举项。
  ///
  /// Creates a [SkipSecondType] with the given [value] in seconds.
  const SkipSecondType({required this.value});

  /// 对应的 [Duration] 时长对象。
  ///
  /// Equivalent [Duration] for this skip step.
  Duration get duration => Duration(seconds: value);
}
