#define WLR_USE_UNSTABLE

#include "src/plugins/PluginAPI.hpp"
#include "src/desktop/state/FocusState.hpp"
#include "src/desktop/state/WindowState.hpp"
#include "src/desktop/view/Window.hpp"
#include "src/event/EventBus.hpp"
#define private public
#include "src/protocols/XDGShell.hpp"
#undef private
#include "src/render/Renderer.hpp"
#include "src/xwayland/XSurface.hpp"
#include "xdg-shell.hpp"

#include <wayland-server.h>

#include <algorithm>
#include <cctype>
#include <format>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

static HANDLE PHANDLE = nullptr;

static std::string canonAddr(std::string spec) {
  if (spec.rfind("address:", 0) == 0)
    spec = spec.substr(8);
  std::transform(spec.begin(), spec.end(), spec.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (!spec.empty() && spec.rfind("0x", 0) != 0)
    spec = "0x" + spec;
  return spec;
}

static std::string windowAddr(PHLWINDOW w) {
  return std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get()));
}

static PHLWINDOW windowBySelector(const std::string& spec) {
  const auto wanted = canonAddr(spec);
  if (wanted.empty() || wanted == "active")
    return Desktop::focusState()->window();

  for (auto& w : Desktop::windowState()->windows()) {
    if (w && windowAddr(w) == wanted)
      return w;
  }
  return nullptr;
}

static PHLWINDOW windowFromLua(lua_State* L) {
  if (lua_istable(L, 1)) {
    lua_getfield(L, 1, "window");
    std::string spec;
    if (lua_isstring(L, -1))
      spec = lua_tostring(L, -1);
    lua_pop(L, 1);
    if (!spec.empty())
      return windowBySelector(spec);
  } else if (lua_isstring(L, 1)) {
    return windowBySelector(lua_tostring(L, 1));
  }
  return Desktop::focusState()->window();
}

static void damageWindow(PHLWINDOW w) {
  if (!w || !g_pHyprRenderer)
    return;
  g_pHyprRenderer->damageWindow(w, true);
  if (auto m = w->m_monitor.lock())
    g_pHyprRenderer->damageMonitor(m);
}

static void setMinimized(PHLWINDOW w, bool minimized) {
  if (!w)
    return;

  damageWindow(w);
  w->setHidden(minimized);
  damageWindow(w);

  if (minimized)
    return;

  Desktop::focusState()->fullWindowFocus(w, Desktop::FOCUS_REASON_DISPATCH_FOCUSWINDOW);
}

static int pushNoOpDispatcher(lua_State* L) {
  lua_getglobal(L, "hl");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 0;
  }
  lua_getfield(L, -1, "dsp");
  lua_remove(L, -2);
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 0;
  }
  lua_getfield(L, -1, "no_op");
  lua_remove(L, -2);
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 1);
    return 0;
  }
  lua_call(L, 0, 1);
  return 1;
}

static int luaMinimize(lua_State* L) {
  setMinimized(windowFromLua(L), true);
  return pushNoOpDispatcher(L);
}

static int luaRestore(lua_State* L) {
  setMinimized(windowFromLua(L), false);
  return pushNoOpDispatcher(L);
}

// Chromium/GTK CSD send xdg_toplevel.set_minimized (and X11 IconicState).
// Caption buttons go through Lua; CSD never did, so Chrome's own minimize
// was a no-op. Honor those protocol requests with the same setHidden path.
struct MinWatch {
  CHyprSignalListener xdg;
  CHyprSignalListener xwm;
};

static std::unordered_map<uintptr_t, MinWatch> g_watches;
static CHyprSignalListener                     g_onCreate;
static CHyprSignalListener                     g_onOpen;
static CHyprSignalListener                     g_onOpenLate;
static CHyprSignalListener                     g_onDestroy;

static std::optional<bool> requestedMinimized(PHLWINDOW w) {
  if (!w)
    return std::nullopt;
  if (auto xdg = w->m_xdgSurface.lock()) {
    if (auto top = xdg->m_toplevel.lock()) {
      if (top->m_state.requestsMinimize.has_value())
        return top->m_state.requestsMinimize;
    }
  }
  if (auto xwm = w->m_xwaylandSurface.lock()) {
    if (xwm->m_state.requestsMinimize.has_value())
      return xwm->m_state.requestsMinimize;
  }
  return std::nullopt;
}

static void applyRequestedMinimize(PHLWINDOWREF ref) {
  auto w = ref.lock();
  if (!w)
    return;
  const auto want = requestedMinimized(w);
  if (!want.has_value())
    return;
  setMinimized(w, *want);
}

static void advertiseWmCapabilities(PHLWINDOW w) {
  if (!w)
    return;
  auto xdg = w->m_xdgSurface.lock();
  if (!xdg)
    return;
  auto top = xdg->m_toplevel.lock();
  if (!top || !top->m_resource)
    return;
  if (top->m_resource->version() < 5)
    return;

  // Chromium only draws min/max CSD if the compositor advertises them.
  wl_array caps;
  wl_array_init(&caps);
  const uint32_t values[] = {
      XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU,
      XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE,
      XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN,
      XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE,
  };
  for (uint32_t value : values) {
    auto* slot = static_cast<uint32_t*>(wl_array_add(&caps, sizeof(uint32_t)));
    if (slot)
      *slot = value;
  }
  top->m_resource->sendWmCapabilities(&caps);
  wl_array_release(&caps);
}

static void watchWindow(PHLWINDOW w) {
  if (!w)
    return;

  const auto key = reinterpret_cast<uintptr_t>(w.get());
  MinWatch   watch;
  bool       attached = false;
  PHLWINDOWREF ref    = w;

  if (auto xdg = w->m_xdgSurface.lock()) {
    if (auto top = xdg->m_toplevel.lock()) {
      watch.xdg   = top->m_events.stateChanged.listen([ref]() { applyRequestedMinimize(ref); });
      attached    = true;
    }
  }
  if (auto xwm = w->m_xwaylandSurface.lock()) {
    watch.xwm  = xwm->m_events.stateChanged.listen([ref]() { applyRequestedMinimize(ref); });
    attached   = true;
  }
  if (!attached)
    return;

  advertiseWmCapabilities(w);
  g_watches.insert_or_assign(key, std::move(watch));
}

static void watchAllWindows() {
  for (auto& w : Desktop::windowState()->windows())
    watchWindow(w);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
  return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
  PHANDLE = handle;

  const std::string HASH        = __hyprland_api_get_hash();
  const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
  if (HASH != CLIENT_HASH) {
    HyprlandAPI::addNotification(PHANDLE, "[omarchy-minimize] header hash does not match running Hyprland", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
    throw std::runtime_error("[omarchy-minimize] Version mismatch");
  }

  HyprlandAPI::addLuaFunction(PHANDLE, "omarchy_minimize", "minimize", luaMinimize);
  HyprlandAPI::addLuaFunction(PHANDLE, "omarchy_minimize", "restore", luaRestore);

  g_onCreate = Event::bus()->m_events.window.create.listen([](PHLWINDOW w) { watchWindow(w); });
  g_onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { watchWindow(w); });
  g_onOpenLate = Event::bus()->m_events.window.openLate.listen([](PHLWINDOW w) { watchWindow(w); });
  g_onDestroy  = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF w) {
    if (auto live = w.lock())
      g_watches.erase(reinterpret_cast<uintptr_t>(live.get()));
  });
  watchAllWindows();

  return {"omarchy-minimize", "In-place native minimize via CWindow::setHidden", "Omarchy Ultimate", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
  g_watches.clear();
  g_onCreate   = {};
  g_onOpen     = {};
  g_onOpenLate = {};
  g_onDestroy  = {};
}
