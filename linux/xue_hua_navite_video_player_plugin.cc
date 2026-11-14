// Linux plugin implementation — libmpv + FlPixelBufferTexture (software rendering) + Pigeon IPC.

#include "include/xue_hua_navite_video_player/xue_hua_navite_video_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <clocale>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#ifdef HAS_XRANDR
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#endif

#include "mpv_player.h"
#include "player_api.g.h"
#include "xue_hua_navite_video_player_plugin_private.h"

using xue_hua_navite_video_player::CoverFrame;
using xue_hua_navite_video_player::MpvPlayer;

static constexpr const gchar* kLinuxCacheUnsupportedMsg =
    "Native media cache is handled in Dart on Linux.";

#define VIDEO_TEXTURE_TYPE (video_texture_get_type())
G_DECLARE_FINAL_TYPE(VideoTexture, video_texture, VIDEO, TEXTURE, FlPixelBufferTexture)

struct _VideoTexture {
  FlPixelBufferTexture parent_instance;
  // Writable back buffer (mpv writes here).
  uint8_t* buffer;
  // Stable front buffer returned to Flutter. copy_pixels memcpy's under the
  // mutex so write can free/realloc `buffer` without UAF on the raster thread.
  uint8_t* front_buffer;
  size_t front_size;
  uint32_t width;
  uint32_t height;
  GMutex mutex;
};

G_DEFINE_TYPE(VideoTexture, video_texture, fl_pixel_buffer_texture_get_type())

static gboolean video_texture_copy_pixels_cb(FlPixelBufferTexture* tex,
                                             const uint8_t** out_buffer,
                                             uint32_t* width,
                                             uint32_t* height,
                                             GError** /*error*/) {
  // 1x1 opaque-black RGBA placeholder so Flutter's GL texture upload succeeds
  // before the first decoded video frame arrives.
  static const uint8_t kPlaceholderPixel[4] = {0x00, 0x00, 0x00, 0xFF};

  VideoTexture* self = VIDEO_TEXTURE(tex);
  g_mutex_lock(&self->mutex);
  if (self->buffer != nullptr && self->width > 0 && self->height > 0) {
    const size_t n = static_cast<size_t>(self->width) * self->height * 4;
    if (self->front_size != n) {
      g_free(self->front_buffer);
      self->front_buffer = static_cast<uint8_t*>(g_malloc(n));
      self->front_size = n;
    }
    std::memcpy(self->front_buffer, self->buffer, n);
    *out_buffer = self->front_buffer;
    *width = self->width;
    *height = self->height;
  } else {
    *out_buffer = kPlaceholderPixel;
    *width = 1;
    *height = 1;
  }
  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static void video_texture_dispose(GObject* obj) {
  VideoTexture* self = VIDEO_TEXTURE(obj);
  g_mutex_lock(&self->mutex);
  g_free(self->buffer);
  self->buffer = nullptr;
  g_free(self->front_buffer);
  self->front_buffer = nullptr;
  self->front_size = 0;
  g_mutex_unlock(&self->mutex);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(video_texture_parent_class)->dispose(obj);
}

static void video_texture_class_init(VideoTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = video_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = video_texture_copy_pixels_cb;
}

static void video_texture_init(VideoTexture* self) {
  g_mutex_init(&self->mutex);
  self->buffer = nullptr;
  self->front_buffer = nullptr;
  self->front_size = 0;
  self->width = 0;
  self->height = 0;
}

static VideoTexture* video_texture_new() {
  return VIDEO_TEXTURE(g_object_new(VIDEO_TEXTURE_TYPE, nullptr));
}

static void video_texture_write(VideoTexture* tex,
                                const uint8_t* src,
                                uint32_t w,
                                uint32_t h) {
  g_mutex_lock(&tex->mutex);
  if (tex->width != w || tex->height != h) {
    g_free(tex->buffer);
    tex->buffer = static_cast<uint8_t*>(g_malloc(static_cast<size_t>(w) * h * 4));
    tex->width = w;
    tex->height = h;
  }
  std::memcpy(tex->buffer, src, static_cast<size_t>(w) * h * 4);
  g_mutex_unlock(&tex->mutex);
}

namespace {

struct PluginAsyncState {
  std::atomic<bool> plugin_alive{true};
  std::atomic<bool> drain_posted{false};
  std::atomic<bool> render_posted{false};
};

struct IdlePayload {
  XueHuaNaviteVideoPlayerPlugin* self;
  std::shared_ptr<PluginAsyncState> state;
};

void destroy_idle_payload(gpointer data) {
  delete static_cast<IdlePayload*>(data);
}

}  // namespace

#define XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), xue_hua_navite_video_player_plugin_get_type(), \
                              XueHuaNaviteVideoPlayerPlugin))

struct _XueHuaNaviteVideoPlayerPlugin {
  GObject parent_instance;
  FlTextureRegistrar* texture_registrar;
  XueHuaNaviteVideoPlayerPlayerFlutterApi* flutter_api;
  VideoTexture* texture;
  int64_t texture_id;
  std::shared_ptr<MpvPlayer>* player;
  std::shared_ptr<PluginAsyncState>* async_state;
  guint drain_timer_id;
  gboolean disposed;
  gchar* backlight_path;
  gint backlight_max;
  gboolean backlight_saved;
  gint saved_backlight;
#ifdef HAS_XRANDR
  XRRCrtcGamma* saved_gamma;
  RRCrtc saved_crtc;
#endif
  FlPluginRegistrar* registrar;
  gulong window_state_handler_id;
};

G_DEFINE_TYPE(XueHuaNaviteVideoPlayerPlugin,
              xue_hua_navite_video_player_plugin,
              g_object_get_type())

const gchar* xue_hua_navite_video_player_aspect_ratio_mode_to_string(
    XueHuaNaviteVideoPlayerNativeAspectRatioMode mode) {
  switch (mode) {
    case XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_FILL:
      return "fill";
    case XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_STRETCH:
      return "stretch";
    case XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_FIT:
    default:
      return "fit";
  }
}

static void on_player_event_complete(GObject* source_object,
                                     GAsyncResult* result,
                                     gpointer /*user_data*/) {
  auto* api = XUE_HUA_NAVITE_VIDEO_PLAYER_PLAYER_FLUTTER_API(source_object);
  g_autoptr(GError) error = nullptr;
  g_autoptr(XueHuaNaviteVideoPlayerPlayerFlutterApiOnPlayerEventResponse) resp =
      xue_hua_navite_video_player_player_flutter_api_on_player_event_finish(api, result, &error);
  (void)resp;
}

static void on_window_fullscreen_complete(GObject* source_object,
                                          GAsyncResult* result,
                                          gpointer /*user_data*/) {
  auto* api = XUE_HUA_NAVITE_VIDEO_PLAYER_PLAYER_FLUTTER_API(source_object);
  g_autoptr(GError) error = nullptr;
  g_autoptr(XueHuaNaviteVideoPlayerPlayerFlutterApiOnWindowFullscreenResponse) resp =
      xue_hua_navite_video_player_player_flutter_api_on_window_fullscreen_finish(api, result,
                                                                                 &error);
  (void)resp;
}

static void emit_player_event(XueHuaNaviteVideoPlayerPlugin* self,
                              XueHuaNaviteVideoPlayerPlayerEventData* event) {
  if (!self->flutter_api || !self->async_state ||
      !(*self->async_state)->plugin_alive.load(std::memory_order_acquire)) {
    return;
  }
  xue_hua_navite_video_player_player_flutter_api_on_player_event(
      self->flutter_api, event, nullptr, on_player_event_complete, nullptr);
}

static void emit_int_event(XueHuaNaviteVideoPlayerPlugin* self,
                           XueHuaNaviteVideoPlayerNativePlayerEventType kind,
                           int64_t value) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(kind, &value, nullptr, nullptr, nullptr,
                                                        nullptr, nullptr, nullptr, nullptr);
  emit_player_event(self, event);
}

static void emit_bool_event(XueHuaNaviteVideoPlayerPlugin* self,
                            XueHuaNaviteVideoPlayerNativePlayerEventType kind,
                            gboolean value) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(kind, nullptr, &value, nullptr, nullptr,
                                                        nullptr, nullptr, nullptr, nullptr);
  emit_player_event(self, event);
}

static void emit_simple_event(XueHuaNaviteVideoPlayerPlugin* self,
                              XueHuaNaviteVideoPlayerNativePlayerEventType kind) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(kind, nullptr, nullptr, nullptr, nullptr,
                                                        nullptr, nullptr, nullptr, nullptr);
  emit_player_event(self, event);
}

static void emit_str_event(XueHuaNaviteVideoPlayerPlugin* self,
                           XueHuaNaviteVideoPlayerNativePlayerEventType kind,
                           const gchar* msg) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(kind, nullptr, nullptr, msg, nullptr,
                                                        nullptr, nullptr, nullptr, nullptr);
  emit_player_event(self, event);
}

static void emit_video_size_event(XueHuaNaviteVideoPlayerPlugin* self,
                                  double width,
                                  double height) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_VIDEO_SIZE, nullptr, nullptr,
          nullptr, &width, &height, nullptr, nullptr, nullptr);
  emit_player_event(self, event);
}

static void send_cast_state(XueHuaNaviteVideoPlayerPlugin* self,
                            XueHuaNaviteVideoPlayerNativeCastState state,
                            const gchar* device_name) {
  const gchar* safe_name = (device_name && strlen(device_name) > 0) ? device_name : nullptr;
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_CAST_STATE, nullptr, nullptr,
          nullptr, nullptr, nullptr, nullptr, &state, safe_name);
  emit_player_event(self, event);
}

static GtkWindow* plugin_window(XueHuaNaviteVideoPlayerPlugin* self) {
  if (!self->registrar) return nullptr;
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (!view) return nullptr;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(toplevel)) return nullptr;
  return GTK_WINDOW(toplevel);
}

static void plugin_notify_window_fullscreen(XueHuaNaviteVideoPlayerPlugin* self,
                                            gboolean fullscreen) {
  if (!self->flutter_api || !self->async_state ||
      !(*self->async_state)->plugin_alive.load(std::memory_order_acquire)) {
    return;
  }
  xue_hua_navite_video_player_player_flutter_api_on_window_fullscreen(
      self->flutter_api, fullscreen, nullptr, on_window_fullscreen_complete, nullptr);
}

static gboolean plugin_on_window_state(GtkWidget* /*widget*/,
                                       GdkEventWindowState* event,
                                       gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if ((event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) == 0) {
    return FALSE;
  }
  const gboolean fs = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  plugin_notify_window_fullscreen(self, fs);
  return FALSE;
}

static void plugin_bind_window_state(XueHuaNaviteVideoPlayerPlugin* self) {
  if (self->window_state_handler_id != 0) return;
  GtkWindow* window = plugin_window(self);
  if (!window) return;
  self->window_state_handler_id = g_signal_connect(
      window, "window-state-event", G_CALLBACK(plugin_on_window_state), self);
}

static void plugin_set_window_fullscreen(XueHuaNaviteVideoPlayerPlugin* self, gboolean enable) {
  plugin_bind_window_state(self);
  GtkWindow* window = plugin_window(self);
  if (!window) return;
  if (enable) {
    gtk_window_fullscreen(window);
  } else {
    gtk_window_unfullscreen(window);
  }
}

static void plugin_restore_window_fullscreen(XueHuaNaviteVideoPlayerPlugin* self) {
  GtkWindow* window = plugin_window(self);
  if (window) {
    gtk_window_unfullscreen(window);
  }
}

static gboolean drain_events_cb(gpointer user_data) {
  auto* payload = static_cast<IdlePayload*>(user_data);
  if (!payload->state->plugin_alive.load(std::memory_order_acquire)) {
    return G_SOURCE_REMOVE;
  }
  payload->state->drain_posted.store(false, std::memory_order_release);
  auto* self = payload->self;
  if (self->disposed || !self->player || !*self->player) return G_SOURCE_REMOVE;
  (*self->player)->DrainEvents();
  return G_SOURCE_REMOVE;
}

static gboolean drain_events_timer_cb(gpointer user_data) {
  auto* self = static_cast<XueHuaNaviteVideoPlayerPlugin*>(user_data);
  if (!self->async_state || !(*self->async_state)->plugin_alive.load(std::memory_order_acquire) ||
      self->disposed || !self->player || !*self->player) {
    return G_SOURCE_REMOVE;
  }
  (*self->player)->DrainEvents();
  return G_SOURCE_CONTINUE;
}

static gboolean render_cb(gpointer user_data) {
  auto* payload = static_cast<IdlePayload*>(user_data);
  if (!payload->state->plugin_alive.load(std::memory_order_acquire)) {
    return G_SOURCE_REMOVE;
  }
  payload->state->render_posted.store(false, std::memory_order_release);
  auto* self = payload->self;
  if (self->disposed || !self->player || !*self->player) return G_SOURCE_REMOVE;
  if ((*self->player)->Render()) {
    if (self->texture) {
      fl_texture_registrar_mark_texture_frame_available(self->texture_registrar,
                                                        FL_TEXTURE(self->texture));
    }
  }
  return G_SOURCE_REMOVE;
}

static void ensure_player(XueHuaNaviteVideoPlayerPlugin* self) {
  if (self->player && *self->player) return;
  self->disposed = FALSE;
  auto player = std::make_shared<MpvPlayer>();
  std::string err;
  if (!player->Initialize(&err)) {
    emit_str_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_ERROR,
                   ("mpv init failed: " + err).c_str());
    return;
  }
  auto state = self->async_state ? *self->async_state : std::make_shared<PluginAsyncState>();
  state->drain_posted.store(false, std::memory_order_release);
  state->render_posted.store(false, std::memory_order_release);

  player->SetWakeupHandler([self, state]() {
    if (!state->plugin_alive.load(std::memory_order_acquire)) return;
    bool expected = false;
    if (state->drain_posted.compare_exchange_strong(expected, true)) {
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, drain_events_cb, new IdlePayload{self, state},
                      destroy_idle_payload);
    }
  });
  player->SetUpdateHandler([self, state]() {
    if (!state->plugin_alive.load(std::memory_order_acquire)) return;
    bool expected = false;
    if (state->render_posted.compare_exchange_strong(expected, true)) {
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, render_cb, new IdlePayload{self, state},
                      destroy_idle_payload);
    }
  });
  player->SetOnPosition([self](int64_t ms) {
    emit_int_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_POSITION, ms);
  });
  player->SetOnBuffered([self](int64_t ms) {
    emit_int_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_BUFFERED, ms);
  });
  player->SetOnDuration([self](int64_t ms) {
    emit_int_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_DURATION, ms);
  });
  player->SetOnPlaying([self](bool p) {
    emit_bool_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_PLAYING, p);
  });
  player->SetOnBuffering([self](bool b) {
    emit_bool_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_BUFFERING, b);
  });
  player->SetOnCompleted([self]() {
    emit_simple_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_COMPLETED);
  });
  player->SetOnError([self](const std::string& m) {
    emit_str_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_ERROR, m.c_str());
  });
  player->SetOnFrame([self](const uint8_t* rgba, uint32_t w, uint32_t h) {
    if (self->disposed || !self->texture) return;
    video_texture_write(self->texture, rgba, w, h);
  });
  player->SetOnVideoSize([self](int64_t w, int64_t h) {
    if (w <= 0 || h <= 0) return;
    emit_video_size_event(self, static_cast<double>(w), static_cast<double>(h));
  });

  if (!self->player) {
    self->player = new std::shared_ptr<MpvPlayer>(std::move(player));
  } else {
    *self->player = std::move(player);
  }
  if (!self->drain_timer_id) {
    self->drain_timer_id = g_timeout_add(100, drain_events_timer_cb, self);
  }
}

static int64_t player_create(XueHuaNaviteVideoPlayerPlugin* self) {
  ensure_player(self);
  if (!self->player || !*self->player) return -1;
  if (!self->texture) {
    self->texture = video_texture_new();
    fl_texture_registrar_register_texture(self->texture_registrar, FL_TEXTURE(self->texture));
    self->texture_id = fl_texture_get_id(FL_TEXTURE(self->texture));
  }
  return self->texture_id;
}

static void player_dispose(XueHuaNaviteVideoPlayerPlugin* self) {
  self->disposed = TRUE;
  if (self->async_state && *self->async_state) {
    (*self->async_state)->drain_posted.store(false, std::memory_order_release);
    (*self->async_state)->render_posted.store(false, std::memory_order_release);
  }
  if (self->drain_timer_id) {
    g_source_remove(self->drain_timer_id);
    self->drain_timer_id = 0;
  }
  if (self->player) {
    delete self->player;
    self->player = nullptr;
  }
  if (self->texture) {
    fl_texture_registrar_unregister_texture(self->texture_registrar, FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
    self->texture_id = -1;
  }
}

static gchar* default_cover_dir() {
  const gchar* tmp = g_get_tmp_dir();
  gchar* dir = g_build_filename(tmp, "xue_hua_navite_video_player", "covers", nullptr);
  g_mkdir_with_parents(dir, 0700);
  return dir;
}

static bool read_int_file(const char* path, int* out) {
  FILE* file = fopen(path, "r");
  if (!file) return false;
  int value = 0;
  const bool ok = fscanf(file, "%d", &value) == 1;
  fclose(file);
  if (ok) *out = value;
  return ok;
}

static bool write_int_file(const char* path, int value) {
  FILE* file = fopen(path, "w");
  if (!file) return false;
  const int written = fprintf(file, "%d", value);
  fclose(file);
  return written > 0;
}

static bool ensure_backlight(XueHuaNaviteVideoPlayerPlugin* self) {
  if (self->backlight_path && self->backlight_max > 0) return true;
  GDir* dir = g_dir_open("/sys/class/backlight", 0, nullptr);
  if (!dir) return false;
  const gchar* name = nullptr;
  int best_max = -1;
  gchar* best_path = nullptr;
  while ((name = g_dir_read_name(dir))) {
    g_autofree gchar* max_path =
        g_build_filename("/sys/class/backlight", name, "max_brightness", nullptr);
    g_autofree gchar* br_path =
        g_build_filename("/sys/class/backlight", name, "brightness", nullptr);
    int max_value = 0;
    if (!read_int_file(max_path, &max_value) || max_value <= 0) continue;
    if (access(br_path, W_OK) != 0) continue;
    if (max_value > best_max) {
      best_max = max_value;
      g_free(best_path);
      best_path = g_strdup(br_path);
    }
  }
  g_dir_close(dir);
  if (!best_path) return false;
  self->backlight_path = best_path;
  self->backlight_max = best_max;
  return true;
}

#ifdef HAS_XRANDR
static bool randr_set_brightness(XueHuaNaviteVideoPlayerPlugin* self, double value) {
  Display* dpy = XOpenDisplay(nullptr);
  if (!dpy) return false;
  const int screen = DefaultScreen(dpy);
  const Window root = RootWindow(dpy, screen);
  XRRScreenResources* res = XRRGetScreenResourcesCurrent(dpy, root);
  if (!res) {
    XCloseDisplay(dpy);
    return false;
  }
  RRCrtc crtc = None;
  for (int i = 0; i < res->noutput; i++) {
    XRROutputInfo* info = XRRGetOutputInfo(dpy, res, res->outputs[i]);
    if (!info) continue;
    if (info->connection == RR_Connected && info->crtc != None) {
      crtc = info->crtc;
      XRRFreeOutputInfo(info);
      break;
    }
    XRRFreeOutputInfo(info);
  }
  if (crtc == None) {
    XRRFreeScreenResources(res);
    XCloseDisplay(dpy);
    return false;
  }
  XRRCrtcGamma* gamma = XRRGetCrtcGamma(dpy, crtc);
  if (!gamma) {
    XRRFreeScreenResources(res);
    XCloseDisplay(dpy);
    return false;
  }
  if (!self->saved_gamma) {
    self->saved_gamma = XRRAllocGamma(gamma->size);
    if (self->saved_gamma) {
      memcpy(self->saved_gamma->red, gamma->red,
             static_cast<size_t>(gamma->size) * sizeof(unsigned short));
      memcpy(self->saved_gamma->green, gamma->green,
             static_cast<size_t>(gamma->size) * sizeof(unsigned short));
      memcpy(self->saved_gamma->blue, gamma->blue,
             static_cast<size_t>(gamma->size) * sizeof(unsigned short));
      self->saved_crtc = crtc;
    }
  }
  XRRCrtcGamma* src = self->saved_gamma ? self->saved_gamma : gamma;
  XRRCrtcGamma* next = XRRAllocGamma(src->size);
  bool ok = false;
  const double clamped = value < 0 ? 0 : (value > 1 ? 1 : value);
  if (next) {
    for (int i = 0; i < src->size; i++) {
      next->red[i] = static_cast<unsigned short>(src->red[i] * clamped + 0.5);
      next->green[i] = static_cast<unsigned short>(src->green[i] * clamped + 0.5);
      next->blue[i] = static_cast<unsigned short>(src->blue[i] * clamped + 0.5);
    }
    XRRSetCrtcGamma(dpy, crtc, next);
    XRRFreeGamma(next);
    ok = true;
  }
  XRRFreeGamma(gamma);
  XRRFreeScreenResources(res);
  XCloseDisplay(dpy);
  return ok;
}

static void randr_restore_brightness(XueHuaNaviteVideoPlayerPlugin* self) {
  if (!self->saved_gamma) return;
  Display* dpy = XOpenDisplay(nullptr);
  if (dpy) {
    XRRSetCrtcGamma(dpy, self->saved_crtc, self->saved_gamma);
    XCloseDisplay(dpy);
  }
  XRRFreeGamma(self->saved_gamma);
  self->saved_gamma = nullptr;
  self->saved_crtc = None;
}
#endif

static double plugin_get_brightness(XueHuaNaviteVideoPlayerPlugin* self) {
  if (ensure_backlight(self)) {
    int current = 0;
    if (read_int_file(self->backlight_path, &current) && self->backlight_max > 0) {
      return static_cast<double>(current) / static_cast<double>(self->backlight_max);
    }
  }
  return 1.0;
}

static void plugin_set_brightness(XueHuaNaviteVideoPlayerPlugin* self, double value) {
  const double clamped = value < 0 ? 0 : (value > 1 ? 1 : value);
  if (ensure_backlight(self)) {
    int original = 0;
    const bool have_original = read_int_file(self->backlight_path, &original);
    const int target = static_cast<int>(self->backlight_max * clamped + 0.5);
    if (write_int_file(self->backlight_path, target)) {
      if (!self->backlight_saved && have_original) {
        self->saved_backlight = original;
        self->backlight_saved = TRUE;
      }
      return;
    }
  }
#ifdef HAS_XRANDR
  randr_set_brightness(self, clamped);
#endif
}

static void plugin_restore_brightness(XueHuaNaviteVideoPlayerPlugin* self) {
  if (self->backlight_saved && self->backlight_path) {
    write_int_file(self->backlight_path, self->saved_backlight);
    self->backlight_saved = FALSE;
  }
#ifdef HAS_XRANDR
  randr_restore_brightness(self);
#endif
}

namespace {

struct DurationJob {
  std::string url;
  int timeout_ms = 15000;
};

struct CoversJob {
  std::string url;
  int count = 5;
  int candidates = 15;
  double min_brightness = 0.08;
  std::string output_dir;
};

struct SnapshotJob {
  std::shared_ptr<MpvPlayer> player;
};

struct SnapshotResult {
  bool ok = false;
  std::vector<uint8_t> bytes;
  std::string error;
};

void duration_job_thread(GTask* task, gpointer, gpointer task_data, GCancellable*) {
  auto* job = static_cast<DurationJob*>(task_data);
  int64_t ms = 0;
  if (!job->url.empty()) {
    ms = MpvPlayer::GetDurationMs(job->url, job->timeout_ms);
  }
  g_task_return_int(task, static_cast<gssize>(ms));
}

void duration_job_done(GObject*, GAsyncResult* res, gpointer user_data) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle) handle =
      XUE_HUA_NAVITE_VIDEO_PLAYER_PLAYER_HOST_API_RESPONSE_HANDLE(user_data);
  const gssize ms = g_task_propagate_int(G_TASK(res), nullptr);
  if (ms > 0) {
    int64_t value = static_cast<int64_t>(ms);
    xue_hua_navite_video_player_player_host_api_respond_get_duration(handle, &value);
  } else {
    xue_hua_navite_video_player_player_host_api_respond_get_duration(handle, nullptr);
  }
}

void covers_job_thread(GTask* task, gpointer, gpointer task_data, GCancellable*) {
  auto* job = static_cast<CoversJob*>(task_data);
  auto* frames = new std::vector<CoverFrame>(MpvPlayer::ExtractCovers(
      job->url, job->count, job->candidates, job->min_brightness, job->output_dir));
  g_task_return_pointer(task, frames, [](gpointer p) {
    delete static_cast<std::vector<CoverFrame>*>(p);
  });
}

void covers_job_done(GObject*, GAsyncResult* res, gpointer user_data) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle) handle =
      XUE_HUA_NAVITE_VIDEO_PLAYER_PLAYER_HOST_API_RESPONSE_HANDLE(user_data);
  auto* frames =
      static_cast<std::vector<CoverFrame>*>(g_task_propagate_pointer(G_TASK(res), nullptr));
  g_autoptr(FlValue) list = fl_value_new_list();
  if (frames) {
    for (const auto& f : *frames) {
      g_autoptr(XueHuaNaviteVideoPlayerCoverFrameData) item =
          xue_hua_navite_video_player_cover_frame_data_new(f.path.c_str(), f.position_ms,
                                                           f.brightness);
      fl_value_append_take(
          list, fl_value_new_custom_object(xue_hua_navite_video_player_cover_frame_data_type_id,
                                           G_OBJECT(item)));
    }
    delete frames;
  }
  xue_hua_navite_video_player_player_host_api_respond_extract_covers(handle, list);
}

void snapshot_job_thread(GTask* task, gpointer, gpointer task_data, GCancellable*) {
  auto* job = static_cast<SnapshotJob*>(task_data);
  auto* result = new SnapshotResult();
  if (job->player) {
    result->ok = job->player->TakeSnapshot(&result->bytes, &result->error);
  } else {
    result->error = "Player not initialized";
  }
  g_task_return_pointer(task, result, [](gpointer p) { delete static_cast<SnapshotResult*>(p); });
}

void snapshot_job_done(GObject*, GAsyncResult* res, gpointer user_data) {
  g_autoptr(XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle) handle =
      XUE_HUA_NAVITE_VIDEO_PLAYER_PLAYER_HOST_API_RESPONSE_HANDLE(user_data);
  auto* out = static_cast<SnapshotResult*>(g_task_propagate_pointer(G_TASK(res), nullptr));
  if (out && out->ok) {
    g_autoptr(XueHuaNaviteVideoPlayerSnapshotData) snapshot =
        xue_hua_navite_video_player_snapshot_data_new(out->bytes.data(), out->bytes.size(),
                                                      nullptr);
    xue_hua_navite_video_player_player_host_api_respond_take_snapshot(handle, snapshot);
  } else {
    const gchar* msg =
        (out && !out->error.empty()) ? out->error.c_str() : "Failed to capture snapshot";
    xue_hua_navite_video_player_player_host_api_respond_error_take_snapshot(
        handle, "SNAPSHOT_FAIL", msg, nullptr);
  }
  delete out;
}

}  // namespace

static void show_linux_cast_picker(XueHuaNaviteVideoPlayerPlugin* self) {
  GtkWindow* parent = plugin_window(self);
  // Launch GNOME Network Displays if installed; otherwise present a status dialog.
  g_autofree gchar* nd_bin = g_find_program_in_path("gnome-network-displays");
  if (nd_bin) {
    GError* err = nullptr;
    if (g_spawn_command_line_async("gnome-network-displays", &err)) {
      send_cast_state(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_CAST_STATE_CONNECTED,
                      "GNOME Network Displays");
      if (self->player && *self->player) (*self->player)->Pause();
      return;
    }
    if (err) g_error_free(err);
  }
  GtkWidget* dialog = gtk_message_dialog_new(
      parent, GTK_DIALOG_DESTROY_WITH_PARENT, GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE,
      "未在当前网络中发现可用的无线投屏接收端（UPnP / Miracast）");
  gtk_window_set_title(GTK_WINDOW(dialog), "选择投屏设备");
  g_signal_connect_swapped(dialog, "response", G_CALLBACK(gtk_widget_destroy), dialog);
  gtk_widget_show_all(dialog);
}

static void stop_linux_casting(XueHuaNaviteVideoPlayerPlugin* self) {
  if (self->player && *self->player) {
    (*self->player)->Pause();
  }
  emit_bool_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_PLAYING, FALSE);
  send_cast_state(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_CAST_STATE_NOT_CONNECTED, nullptr);
}

// ---------------------------------------------------------------------------
// PlayerHostApi vtable handlers
// ---------------------------------------------------------------------------

static void host_create(XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                        gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  const int64_t id = player_create(self);
  if (id < 0) {
    xue_hua_navite_video_player_player_host_api_respond_error_create(
        response_handle, "CREATE_FAIL", "Failed to initialize native player", nullptr);
    return;
  }
  send_cast_state(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_CAST_STATE_NOT_CONNECTED, nullptr);
  xue_hua_navite_video_player_player_host_api_respond_create(response_handle, id);
}

static void host_open(XueHuaNaviteVideoPlayerOpenMediaRequest* request,
                      XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                      gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  ensure_player(self);
  const gchar* url = xue_hua_navite_video_player_open_media_request_get_url(request);
  if (url && strlen(url) > 0 && self->player && *self->player) {
    (*self->player)->Open(url);
    emit_bool_event(self, XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_BUFFERING, TRUE);
  }
  xue_hua_navite_video_player_player_host_api_respond_open(response_handle);
}

static XueHuaNaviteVideoPlayerPlayerHostApiPlayResponse* host_play(gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (self->player && *self->player) (*self->player)->Play();
  return xue_hua_navite_video_player_player_host_api_play_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiPauseResponse* host_pause(gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (self->player && *self->player) (*self->player)->Pause();
  return xue_hua_navite_video_player_player_host_api_pause_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSeekResponse* host_seek(int64_t position_ms,
                                                                   gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (self->player && *self->player) (*self->player)->Seek(position_ms);
  return xue_hua_navite_video_player_player_host_api_seek_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetVolumeResponse* host_set_volume(double volume,
                                                                              gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (self->player && *self->player) (*self->player)->SetVolume(volume);
  return xue_hua_navite_video_player_player_host_api_set_volume_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetSpeedResponse* host_set_speed(double speed,
                                                                            gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (self->player && *self->player) (*self->player)->SetSpeed(speed);
  return xue_hua_navite_video_player_player_host_api_set_speed_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetAspectRatioModeResponse* host_set_aspect_ratio_mode(
    XueHuaNaviteVideoPlayerNativeAspectRatioMode mode,
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  ensure_player(self);
  if (self->player && *self->player) {
    (*self->player)->SetAspectRatioMode(xue_hua_navite_video_player_aspect_ratio_mode_to_string(mode));
  }
  return xue_hua_navite_video_player_player_host_api_set_aspect_ratio_mode_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetVideoViewSizeResponse* host_set_video_view_size(
    double width,
    double height,
    double device_pixel_ratio,
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  ensure_player(self);
  if (self->player && *self->player) {
    const double ratio = device_pixel_ratio > 0.0 ? device_pixel_ratio : 1.0;
    (*self->player)
        ->SetVideoViewSize(static_cast<uint32_t>(width * ratio + 0.5),
                           static_cast<uint32_t>(height * ratio + 0.5));
  }
  return xue_hua_navite_video_player_player_host_api_set_video_view_size_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiShowCastPickerResponse* host_show_cast_picker(
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  show_linux_cast_picker(self);
  return xue_hua_navite_video_player_player_host_api_show_cast_picker_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiStopCastingResponse* host_stop_casting(
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  stop_linux_casting(self);
  return xue_hua_navite_video_player_player_host_api_stop_casting_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiDisposeResponse* host_dispose(gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  plugin_restore_brightness(self);
  player_dispose(self);
  return xue_hua_navite_video_player_player_host_api_dispose_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiGetBrightnessResponse* host_get_brightness(
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  return xue_hua_navite_video_player_player_host_api_get_brightness_response_new(
      plugin_get_brightness(self));
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetBrightnessResponse* host_set_brightness(
    double value,
    gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  plugin_set_brightness(self, value);
  return xue_hua_navite_video_player_player_host_api_set_brightness_response_new();
}

static XueHuaNaviteVideoPlayerPlayerHostApiSetWindowFullscreenResponse*
host_set_window_fullscreen(gboolean value, gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  plugin_set_window_fullscreen(self, value);
  return xue_hua_navite_video_player_player_host_api_set_window_fullscreen_response_new();
}

static void host_take_snapshot(XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                               gpointer user_data) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(user_data);
  if (!self->player || !*self->player) {
    xue_hua_navite_video_player_player_host_api_respond_error_take_snapshot(
        response_handle, "NO_PLAYER", "Player not initialized", nullptr);
    return;
  }
  // Offload synchronous mpv screenshot-to-file I/O off the merged UI/GTK main thread.
  auto* job = new SnapshotJob{*self->player};
  g_autoptr(GTask) task =
      g_task_new(nullptr, nullptr, snapshot_job_done, g_object_ref(response_handle));
  g_task_set_task_data(task, job, [](gpointer p) { delete static_cast<SnapshotJob*>(p); });
  g_task_run_in_thread(task, snapshot_job_thread);
}

static void host_get_duration(XueHuaNaviteVideoPlayerDurationProbeRequest* request,
                              XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                              gpointer /*user_data*/) {
  const gchar* raw_url = xue_hua_navite_video_player_duration_probe_request_get_url(request);
  const int64_t raw_timeout =
      xue_hua_navite_video_player_duration_probe_request_get_timeout_ms(request);
  const int timeout_ms = raw_timeout > 0 ? static_cast<int>(raw_timeout) : 15000;
  auto* job = new DurationJob{raw_url ? raw_url : "", timeout_ms};
  g_autoptr(GTask) task =
      g_task_new(nullptr, nullptr, duration_job_done, g_object_ref(response_handle));
  g_task_set_task_data(task, job, [](gpointer p) { delete static_cast<DurationJob*>(p); });
  g_task_run_in_thread(task, duration_job_thread);
}

static void host_extract_covers(XueHuaNaviteVideoPlayerCoverExtractRequest* request,
                                XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                                gpointer /*user_data*/) {
  const gchar* raw_url = xue_hua_navite_video_player_cover_extract_request_get_url(request);
  const int count =
      static_cast<int>(xue_hua_navite_video_player_cover_extract_request_get_count(request));
  const int candidates =
      static_cast<int>(xue_hua_navite_video_player_cover_extract_request_get_candidates(request));
  const double min_brightness =
      xue_hua_navite_video_player_cover_extract_request_get_min_brightness(request);
  const gchar* raw_dir = xue_hua_navite_video_player_cover_extract_request_get_output_dir(request);

  std::string output_dir = raw_dir ? raw_dir : "";
  if (output_dir.empty()) {
    g_autofree gchar* d = default_cover_dir();
    output_dir = d ? d : "";
  } else {
    g_mkdir_with_parents(output_dir.c_str(), 0700);
  }

  auto* job =
      new CoversJob{raw_url ? raw_url : "", count, candidates, min_brightness, output_dir};
  g_autoptr(GTask) task =
      g_task_new(nullptr, nullptr, covers_job_done, g_object_ref(response_handle));
  g_task_set_task_data(task, job, [](gpointer p) { delete static_cast<CoversJob*>(p); });
  g_task_run_in_thread(task, covers_job_thread);
}

static void host_configure_cache(
    XueHuaNaviteVideoPlayerCacheConfigRequest* /*request*/,
    XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
    gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_configure_cache(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static void host_precache(XueHuaNaviteVideoPlayerPrecacheRequest* /*request*/,
                          XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                          gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_precache(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static XueHuaNaviteVideoPlayerPlayerHostApiCancelPrecacheResponse* host_cancel_precache(
    const gchar* /*cache_key*/,
    gpointer /*user_data*/) {
  return xue_hua_navite_video_player_player_host_api_cancel_precache_response_new_error(
      "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static void host_is_cached(XueHuaNaviteVideoPlayerCacheEntryRequest* /*request*/,
                           XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                           gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_is_cached(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static void host_get_cache_size(
    const gchar* /*cache_dir*/,
    XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
    gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_get_cache_size(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static void host_remove_cache(XueHuaNaviteVideoPlayerCacheEntryRequest* /*request*/,
                              XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                              gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_remove_cache(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static void host_clear_cache(const gchar* /*cache_dir*/,
                             XueHuaNaviteVideoPlayerPlayerHostApiResponseHandle* response_handle,
                             gpointer /*user_data*/) {
  xue_hua_navite_video_player_player_host_api_respond_error_clear_cache(
      response_handle, "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static XueHuaNaviteVideoPlayerPlayerHostApiPinCacheKeyResponse* host_pin_cache_key(
    const gchar* /*cache_key*/,
    gpointer /*user_data*/) {
  return xue_hua_navite_video_player_player_host_api_pin_cache_key_response_new_error(
      "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static XueHuaNaviteVideoPlayerPlayerHostApiUnpinCacheKeyResponse* host_unpin_cache_key(
    const gchar* /*cache_key*/,
    gpointer /*user_data*/) {
  return xue_hua_navite_video_player_player_host_api_unpin_cache_key_response_new_error(
      "UNSUPPORTED", kLinuxCacheUnsupportedMsg, nullptr);
}

static const XueHuaNaviteVideoPlayerPlayerHostApiVTable kHostApiVTable = {
    .create = host_create,
    .open = host_open,
    .play = host_play,
    .pause = host_pause,
    .seek = host_seek,
    .set_volume = host_set_volume,
    .set_speed = host_set_speed,
    .set_aspect_ratio_mode = host_set_aspect_ratio_mode,
    .set_video_view_size = host_set_video_view_size,
    .show_cast_picker = host_show_cast_picker,
    .stop_casting = host_stop_casting,
    .dispose = host_dispose,
    .get_brightness = host_get_brightness,
    .set_brightness = host_set_brightness,
    .set_window_fullscreen = host_set_window_fullscreen,
    .take_snapshot = host_take_snapshot,
    .get_duration = host_get_duration,
    .extract_covers = host_extract_covers,
    .configure_cache = host_configure_cache,
    .precache = host_precache,
    .cancel_precache = host_cancel_precache,
    .is_cached = host_is_cached,
    .get_cache_size = host_get_cache_size,
    .remove_cache = host_remove_cache,
    .clear_cache = host_clear_cache,
    .pin_cache_key = host_pin_cache_key,
    .unpin_cache_key = host_unpin_cache_key,
};

// ---------------------------------------------------------------------------
// GObject lifecycle & plugin registration
// ---------------------------------------------------------------------------

static void xue_hua_navite_video_player_plugin_dispose(GObject* object) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(object);
  if (self->async_state && *self->async_state) {
    (*self->async_state)->plugin_alive.store(false, std::memory_order_release);
  }
  plugin_restore_window_fullscreen(self);
  if (self->window_state_handler_id != 0) {
    GtkWindow* window = plugin_window(self);
    if (window) {
      g_signal_handler_disconnect(window, self->window_state_handler_id);
    }
    self->window_state_handler_id = 0;
  }
  plugin_restore_brightness(self);
  g_clear_pointer(&self->backlight_path, g_free);
  player_dispose(self);
  g_clear_object(&self->flutter_api);
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(xue_hua_navite_video_player_plugin_parent_class)->dispose(object);
}

static void xue_hua_navite_video_player_plugin_finalize(GObject* object) {
  auto* self = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(object);
  delete self->async_state;
  self->async_state = nullptr;
  G_OBJECT_CLASS(xue_hua_navite_video_player_plugin_parent_class)->finalize(object);
}

static void xue_hua_navite_video_player_plugin_class_init(
    XueHuaNaviteVideoPlayerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = xue_hua_navite_video_player_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = xue_hua_navite_video_player_plugin_finalize;
}

static void xue_hua_navite_video_player_plugin_init(XueHuaNaviteVideoPlayerPlugin* self) {
  self->flutter_api = nullptr;
  self->texture = nullptr;
  self->texture_id = -1;
  self->player = nullptr;
  self->async_state =
      new std::shared_ptr<PluginAsyncState>(std::make_shared<PluginAsyncState>());
  self->drain_timer_id = 0;
  self->disposed = FALSE;
  self->backlight_path = nullptr;
  self->backlight_max = 0;
  self->backlight_saved = FALSE;
  self->saved_backlight = 0;
#ifdef HAS_XRANDR
  self->saved_gamma = nullptr;
  self->saved_crtc = None;
#endif
  self->registrar = nullptr;
  self->window_state_handler_id = 0;
}

void xue_hua_navite_video_player_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // libmpv hard-requires LC_NUMERIC=C; otherwise mpv_create() fails outright.
  std::setlocale(LC_NUMERIC, "C");

  XueHuaNaviteVideoPlayerPlugin* plugin = XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN(
      g_object_new(xue_hua_navite_video_player_plugin_get_type(), nullptr));

  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  plugin->flutter_api = xue_hua_navite_video_player_player_flutter_api_new(
      fl_plugin_registrar_get_messenger(registrar), nullptr);
  plugin_bind_window_state(plugin);

  xue_hua_navite_video_player_player_host_api_set_method_handlers(
      fl_plugin_registrar_get_messenger(registrar), nullptr, &kHostApiVTable,
      g_object_ref(plugin), g_object_unref);

  ensure_player(plugin);
  g_object_unref(plugin);
}
