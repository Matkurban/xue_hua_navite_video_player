# VideoPlayerTheme

`ThemeExtension<VideoPlayerTheme>`. Register on `ThemeData.extensions`.

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      VideoPlayerTheme(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
      ),
    ],
  ),
);
```

## Constructor defaults

```dart
const VideoPlayerTheme({
  this.foregroundColor = Colors.white,
  this.backgroundColor = Colors.black,
  this.centerControlsSpacing = 48,
  this.centerPlayButtonIconSize = 24,
  this.centerSkipButtonIconSize = 22,
  this.centerButtonBackgroundColor = const Color(0x4D000000), // black38
  this.chromeIconSize = 20,
  this.topBarPadding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  this.bottomBarPadding = const EdgeInsets.fromLTRB(16, 6, 16, 14),
  this.timeTextStyle = const TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    fontWeight: FontWeight.w500,
    height: 1.0,
  ),
  this.scrubberActiveColor = Colors.white,
  this.scrubberBufferedColor = const Color(0xB3FFFFFF),
  this.scrubberInactiveColor = const Color(0x40FFFFFF),
  this.scrubberThumbColor = Colors.white,
  this.scrubberThumbShadowColor = const Color(0x40000000),
  this.scrubberTrackHeight = 2.0,
  this.scrubberActiveTrackHeight = 6.0,
  this.scrubberThumbRadius = 5.0,
  this.scrubberActiveThumbRadius = 9.0,
  this.menuBackgroundColor = const Color(0xF01A1A1A),
  this.menuBorderRadius = const BorderRadius.all(Radius.circular(10)),
  this.menuContentPadding = const EdgeInsets.symmetric(horizontal: 12),
  this.menuMinVerticalPadding = 4,
  this.menuItemTextStyle = const TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  ),
  this.menuIconSize = 20,
  this.hudBackgroundColor = const Color(0xB3000000),
  this.hudBorderRadius = const BorderRadius.all(Radius.circular(12)),
  this.hudPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  this.hudIconSize = 20,
  this.hudIconGap = 8,
  this.hudTextStyle = const TextStyle(color: Colors.white, fontSize: 16),
});
```

## Fields

| Field | Type | Role |
|-------|------|------|
| `foregroundColor` | `Color` | Overlay glyphs and text. |
| `backgroundColor` | `Color` | Behind the video frame. |
| `centerControlsSpacing` | `double` | Gap between the three center buttons. |
| `centerPlayButtonIconSize` | `double` | Center play/pause icon. |
| `centerSkipButtonIconSize` | `double` | Skip icons. |
| `centerButtonBackgroundColor` | `Color` | Center button fill. |
| `chromeIconSize` | `double` | Top/bottom chrome icons (mute, fullscreen). |
| `topBarPadding` | `EdgeInsets` | Top bar inset. |
| `bottomBarPadding` | `EdgeInsets` | Bottom scrubber row inset. |
| `timeTextStyle` | `TextStyle` | Time labels beside the scrubber. |
| `scrubberActiveColor` | `Color` | Played segment. |
| `scrubberBufferedColor` | `Color` | Buffered segment. |
| `scrubberInactiveColor` | `Color` | Unplayed track. |
| `scrubberThumbColor` | `Color` | Thumb fill. |
| `scrubberThumbShadowColor` | `Color` | Soft glow under the thumb. |
| `scrubberTrackHeight` | `double` | Track thickness at rest. |
| `scrubberActiveTrackHeight` | `double` | Track thickness while scrubbing. |
| `scrubberThumbRadius` | `double` | Thumb radius at rest. |
| `scrubberActiveThumbRadius` | `double` | Thumb radius while pressing/dragging. |
| `menuBackgroundColor` | `Color` | Popup menu panel. |
| `menuBorderRadius` | `BorderRadius` | Menu corners. |
| `menuContentPadding` | `EdgeInsets` | Horizontal padding in menu tiles. |
| `menuMinVerticalPadding` | `double` | Vertical padding in menu tiles. |
| `menuItemTextStyle` | `TextStyle` | Menu title style. |
| `menuIconSize` | `double` | Menu leading/trailing icons. |
| `hudBackgroundColor` | `Color` | Gesture HUD panel. |
| `hudBorderRadius` | `BorderRadius` | HUD corners. |
| `hudPadding` | `EdgeInsets` | HUD inner padding. |
| `hudIconSize` | `double` | HUD icon. |
| `hudIconGap` | `double` | Gap between HUD icon and label. |
| `hudTextStyle` | `TextStyle` | HUD label. |

## Methods

### `static VideoPlayerTheme of(BuildContext context)`

`Theme.of(context).extension<VideoPlayerTheme>() ?? const VideoPlayerTheme()`.

### `VideoPlayerTheme copyWith({...})`

Every field optional (`Color?`, `double?`, `EdgeInsets?`, `TextStyle?`, `BorderRadius?`). Null keeps the current value. Returns a new `VideoPlayerTheme`.

### `VideoPlayerTheme lerp(ThemeExtension<VideoPlayerTheme>? other, double t)`

If `other` is not `VideoPlayerTheme`, returns `this`. Otherwise interpolates colors (`Color.lerp`), doubles (`lerpDouble`), `EdgeInsets.lerp`, `BorderRadius.lerp`, `TextStyle.lerp`. Required by `ThemeExtension`.
