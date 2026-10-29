import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/app_theme.dart';
import 'package:xue_hua_navite_video_player_example/pages/home_page.dart';
import 'package:xue_hua_navite_video_player_example/pages/live_photo_demo_page.dart';
import 'package:xue_hua_navite_video_player_example/widgets/design_style_selector.dart';

export 'models/demo_item.dart';
export 'pages/home_page.dart';
export 'pages/live_photo_demo_page.dart';
export 'pages/live_photo_fullscreen_page.dart';
export 'pages/player_page.dart';
export 'widgets/cache_manager_sheet.dart';
export 'widgets/covers_dialog.dart';
export 'widgets/design_style_selector.dart';
export 'widgets/navite_file_image.dart';
export 'widgets/snapshot_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

/// Boots the example app for integration / driver tests.
Future<void> startExampleApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

/// Boots only [LivePhotoDemoPage] so flutter drive stays on one screen.
Future<void> startLivePhotoDemoApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const LivePhotoDemoApp());
}

/// Minimal app shell whose home is the live-photo demo (driver / IT).
class LivePhotoDemoApp extends StatelessWidget {
  const LivePhotoDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playerTheme = resolveExamplePlayerTheme(playerStyleSignal.value);
        return MaterialApp(
          title: 'Live Photo Demo',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.light.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          darkTheme: AppTheme.dark.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          home: const LivePhotoDemoPage(),
        );
      },
    );
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playerTheme = resolveExamplePlayerTheme(playerStyleSignal.value);
        return MaterialApp(
          title: 'Video Player',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.light.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          darkTheme: AppTheme.dark.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
