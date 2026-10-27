/// MIME 类型检测器，根据文件扩展名或协议推断媒体类型。
/// MIME type detector that infers media type from file extension or URI scheme.
class MimeDetector {
  static const _extensionMap = {
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.flv': 'video/x-flv',
    '.wmv': 'video/x-ms-wmv',
    '.ts': 'video/mp2t',
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
    '.opus': 'audio/opus',
    '.wav': 'audio/wav',
    '.flac': 'audio/flac',
    '.wma': 'audio/x-ms-wma',
  };

  static const _imageExtensions = <String>[
    '.jpg',
    '.jpeg',
    '.heic',
    '.heif',
    '.avif',
    '.png',
    '.webp',
    '.pvt',
  ];

  /// 根据 URL 检测 MIME 类型。
  /// Detects MIME type from the given URL.
  static String detect(String url) {
    if (url.startsWith('livephoto://')) {
      return 'video/mp4';
    }
    if (url.startsWith('data:')) {
      final semicolon = url.indexOf(';');
      final comma = url.indexOf(',');
      final end = semicolon != -1 ? semicolon : comma;
      if (end > 5) {
        return url.substring(5, end);
      }
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return 'application/octet-stream';

    final path = uri.path.toLowerCase();
    for (final entry in _extensionMap.entries) {
      if (path.endsWith(entry.key)) return entry.value;
    }
    return 'application/octet-stream';
  }

  /// 判断路径或 URL 是否为可能携带动态照片的静态图片或 `.pvt` 包扩展名。
  ///
  /// Returns `true` if [url] ends with an image or `.pvt` Live Photo bundle extension.
  static bool isCandidateLivePhotoContainer(String url) {
    if (url.startsWith('livephoto://')) return true;
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    for (final ext in _imageExtensions) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }

  /// 判断是否为视频 MIME 类型。
  /// Checks whether the MIME type is a video type.
  static bool isVideo(String mimeType) => mimeType.startsWith('video/');

  /// 判断是否为音频 MIME 类型。
  /// Checks whether the MIME type is an audio type.
  static bool isAudio(String mimeType) => mimeType.startsWith('audio/');
}
