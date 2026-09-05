/* Exercise the installed Plymouth script plugin, image loader, and compositor.
 * Only display I/O and the timer are replaced; no daemon, VT, or root is used.
 * The driver uses the public plugin ABI, not Plymouth's private script structs.
 */
#include <dlfcn.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <png.h>
#include <ply-boot-splash-plugin.h>
#include <ply-pixel-buffer.h>

struct _ply_pixel_display {
  unsigned long width, height;
  ply_pixel_buffer_t *buffer;
  ply_pixel_display_draw_handler_t draw;
  void *draw_data;
  bool dirty;
  int paused;
};

static ply_event_loop_timeout_handler_t timer;
static void *timer_data;

unsigned long ply_pixel_display_get_width(ply_pixel_display_t *display) { return display->width; }
unsigned long ply_pixel_display_get_height(ply_pixel_display_t *display) { return display->height; }
int ply_pixel_display_get_device_scale(ply_pixel_display_t *display) { (void) display; return 1; }
bool ply_console_viewer_preferred(void) { return false; }
/* The fake display has no console viewer. Console/VT output is outside
 * this offscreen graphics test. */
void ply_console_viewer_hide(void *viewer) { (void) viewer; }

void ply_pixel_display_set_draw_handler(ply_pixel_display_t *display, ply_pixel_display_draw_handler_t handler, void *data) {
  display->draw = handler;
  display->draw_data = data;
}

static void flush_display(ply_pixel_display_t *display) {
  if (display->dirty && !display->paused && display->draw) {
    display->draw(display->draw_data, display->buffer, 0, 0, display->width, display->height, display);
    display->dirty = false;
  }
}

void ply_pixel_display_draw_area(ply_pixel_display_t *display, int x, int y, int width, int height) {
  (void) x; (void) y; (void) width; (void) height;
  display->dirty = true;
  flush_display(display);
}

void ply_pixel_display_pause_updates(ply_pixel_display_t *display) { display->paused++; }
void ply_pixel_display_unpause_updates(ply_pixel_display_t *display) {
  display->paused--;
  flush_display(display);
}

void ply_event_loop_watch_for_timeout(ply_event_loop_t *loop, double seconds, ply_event_loop_timeout_handler_t handler, void *data) {
  (void) loop; (void) seconds;
  timer = handler;
  timer_data = data;
}

void ply_event_loop_stop_watching_for_timeout(ply_event_loop_t *loop, ply_event_loop_timeout_handler_t handler, void *data) {
  (void) loop;
  if (handler == timer && data == timer_data) timer = NULL;
}

static void require(bool condition, const char *message) {
  if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}

static double now(void) {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec + value.tv_nsec / 1e9;
}

static void snapshot(ply_pixel_display_t *display, const char *output, int frame) {
  uint32_t *pixels = ply_pixel_buffer_get_argb32_data(display->buffer);
  uint64_t hash = UINT64_C(14695981039346656037);
  unsigned long foreground = 0;
  for (unsigned long i = 0; i < display->width * display->height; i++) {
    hash = (hash ^ pixels[i]) * UINT64_C(1099511628211);
    if (pixels[i] != pixels[0]) foreground++;
  }
  printf("%d,%lu,%" PRIu64 "\n", frame, foreground, hash);
  if (strcmp(output, "-") == 0) return;
  char filename[4096];
  require(snprintf(filename, sizeof(filename), "%s/frame-%04d.png", output, frame) < (int) sizeof(filename), "Output path too long");
  /* Convert explicitly so this also works on hosts with a different byte order. */
  png_image image = { .version = PNG_IMAGE_VERSION, .width = display->width, .height = display->height, .format = PNG_FORMAT_RGBA };
  unsigned char *rgba = malloc(display->width * display->height * 4);
  require(rgba != NULL, "Unable to allocate PNG buffer");
  for (unsigned long i = 0; i < display->width * display->height; i++) {
    rgba[i * 4] = pixels[i] >> 16;
    rgba[i * 4 + 1] = pixels[i] >> 8;
    rgba[i * 4 + 2] = pixels[i];
    rgba[i * 4 + 3] = pixels[i] >> 24;
  }
  require(png_image_write_to_file(&image, filename, 0, rgba, 0, NULL), image.message);
  png_image_free(&image);
  free(rgba);
}

int main(int argc, char **argv) {
  require(argc == 6 || argc == 7 || argc == 9, "Usage: plymouth-render <plugin.so> <theme.plymouth> <mode> <frames> <output-dir|-> [normal|password|interrupt|late-password|progress|message] [width height]");
  int frames = atoi(argv[4]);
  require(frames > 0 && frames <= 1000, "Frames must be between 1 and 1000");
  int width = argc == 9 ? atoi(argv[7]) : 1280;
  int height = argc == 9 ? atoi(argv[8]) : 720;
  require(width > 0 && height > 0 && width <= 4096 && height <= 4096, "Invalid display dimensions");
  const char *scenario = argc >= 7 ? argv[6] : "normal";
  require(!strcmp(scenario, "normal") || !strcmp(scenario, "password") || !strcmp(scenario, "interrupt") || !strcmp(scenario, "late-password") || !strcmp(scenario, "progress") || !strcmp(scenario, "message"), "Unknown scenario");
  ply_boot_splash_mode_t mode = PLY_BOOT_SPLASH_MODE_INVALID;
  if (!strcmp(argv[3], "boot")) mode = PLY_BOOT_SPLASH_MODE_BOOT_UP;
  if (!strcmp(argv[3], "shutdown")) mode = PLY_BOOT_SPLASH_MODE_SHUTDOWN;
  if (!strcmp(argv[3], "reboot")) mode = PLY_BOOT_SPLASH_MODE_REBOOT;
  if (!strcmp(argv[3], "updates")) mode = PLY_BOOT_SPLASH_MODE_UPDATES;
  require(mode != PLY_BOOT_SPLASH_MODE_INVALID, "Unknown mode");

  void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  require(module != NULL, dlerror());
  ply_boot_splash_plugin_interface_t *(*get_interface)(void) = dlsym(module, "ply_boot_splash_plugin_get_interface");
  void *(*parse_file)(const char *) = dlsym(module, "script_parse_file");
  void (*free_op)(void *) = dlsym(module, "script_parse_op_free");
  require(get_interface && parse_file && free_op, "Missing Plymouth plugin/parser API");
  ply_key_file_t *key_file = ply_key_file_new(argv[2]);
  require(ply_key_file_load(key_file), "Cannot load theme descriptor");
  char *script_path = ply_key_file_get_value(key_file, "script", "ScriptFile");
  require(script_path != NULL, "Theme has no ScriptFile");
  void *op = parse_file(script_path);
  require(op != NULL, "Plymouth script failed to parse");
  free_op(op);
  free(script_path);

  ply_boot_splash_plugin_interface_t *api = get_interface();
  ply_boot_splash_plugin_t *plugin = api->create_plugin(key_file);
  ply_event_loop_t *loop = ply_event_loop_new();
  ply_pixel_display_t display = { .width = width, .height = height };
  display.buffer = ply_pixel_buffer_new(width, height);
  api->add_pixel_display(plugin, &display);
  double started = now();
  require(api->show_splash_screen(plugin, loop, NULL, mode), "Cannot show the native theme");
  double initialization = now() - started;
  api->display_normal(plugin);
  if (!strcmp(scenario, "password")) api->display_password(plugin, "Unlock test volume", 4);
  printf("frame,foreground,hash\n");
  snapshot(&display, argv[5], 0);
  double elapsed = 0;
  double slowest = 0;
  for (int frame = 1; frame <= frames; frame++) {
    if (!strcmp(scenario, "interrupt") && frame == 25) api->display_password(plugin, "Unlock test volume", 4);
    if (!strcmp(scenario, "interrupt") && frame == 50) api->display_normal(plugin);
    if (!strcmp(scenario, "message") && frame == 100) api->display_message(plugin, "Test shutdown message");
    if (!strcmp(scenario, "message") && frame == 140) api->hide_message(plugin, "Test shutdown message");
    if (!strcmp(scenario, "password") && frame == 25) api->display_normal(plugin);
    if (!strcmp(scenario, "late-password") && frame == 85) api->display_password(plugin, "Unlock test volume", 4);
    if (!strcmp(scenario, "progress") && frame == 1) api->display_password(plugin, "Unlock test volume", 4);
    if (!strcmp(scenario, "progress") && frame == 25) api->display_normal(plugin);
    if (!strcmp(scenario, "progress") && frame == 30) api->on_boot_progress(plugin, 1, 0.4);
    if (!strcmp(scenario, "progress") && frame == 31) api->on_boot_progress(plugin, 2, 0.4);
    if (!strcmp(scenario, "progress") && frame == 60) api->on_boot_progress(plugin, 3, 0.2);
    if (!strcmp(scenario, "progress") && frame == 90) api->on_boot_progress(plugin, 4, 0.8);
    started = now();
    require(timer != NULL, "Plymouth stopped refreshing unexpectedly");
    timer(timer_data, loop);
    double frame_time = now() - started;
    elapsed += frame_time;
    if (frame_time > slowest) slowest = frame_time;
    snapshot(&display, argv[5], frame);
  }
  fprintf(stderr, "native: init=%.1fms average-frame=%.2fms slowest-frame=%.2fms\n", initialization * 1000, elapsed / frames * 1000, slowest * 1000);
  api->hide_splash_screen(plugin, loop);
  api->remove_pixel_display(plugin, &display);
  api->destroy_plugin(plugin);
  ply_pixel_buffer_free(display.buffer);
  ply_event_loop_free(loop);
  ply_key_file_free(key_file);
  dlclose(module);
  return 0;
}
