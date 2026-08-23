#define WLR_USE_UNSTABLE

#include "src/plugins/PluginAPI.hpp"
#include "src/desktop/state/FocusState.hpp"
#include "src/desktop/state/WindowState.hpp"
#include "src/desktop/view/Window.hpp"
#include "src/event/EventBus.hpp"
#define private public
#include "src/protocols/XDGShell.hpp"
#include "src/protocols/XDGDecoration.hpp"
#include "src/protocols/ServerDecorationKDE.hpp"
#undef private
#include "xdg-decoration-unstable-v1.hpp"
#include "src/render/Renderer.hpp"
#include "src/xwayland/XSurface.hpp"
#include "src/managers/fullscreen/FullscreenController.hpp"
#include "src/managers/eventLoop/EventLoopManager.hpp"
#include "src/config/shared/actions/ConfigActions.hpp"
#include "src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp"
#include "src/helpers/MiscFunctions.hpp"
#include "src/output/Monitor.hpp"
#include "xdg-shell.hpp"

#include <wayland-server.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <format>
#include <functional>
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
  CHyprSignalListener resize;
};

struct SavedFloat {
  Vector2D pos;
  Vector2D size;
};

static std::unordered_map<uintptr_t, MinWatch>   g_watches;
static std::unordered_map<uintptr_t, SavedFloat> g_savedFloat;
static CHyprSignalListener                     g_onCreate;
static CHyprSignalListener                     g_onOpen;
static CHyprSignalListener                     g_onOpenLate;
static CHyprSignalListener                     g_onDestroy;
static CHyprSignalListener                     g_onFullscreen;
static CHyprSignalListener                     g_onUpdateRules;
static Desktop::Rule::CWindowRuleEffectContainer::storageType g_nobarEffectIdx = 0;
static bool                                    g_inPluginApply = false;

// xdg stateChanged runs inside wl_event_loop_dispatch. Calling
// setFullscreenMode / setMaximized from that stack throws
// std::bad_variant_access and aborts Hyprland (Chrome/Cursor map, 15:49
// and 03:23). Apply on the event-loop idle after the request finishes.
static void later(std::function<void()> fn) {
  if (!g_pEventLoopManager)
    return;
  g_pEventLoopManager->doLater(std::move(fn));
}

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

static std::optional<bool> requestedMaximized(PHLWINDOW w) {
  if (!w)
    return std::nullopt;
  if (auto xdg = w->m_xdgSurface.lock()) {
    if (auto top = xdg->m_toplevel.lock()) {
      if (top->m_state.requestsMaximize.has_value())
        return top->m_state.requestsMaximize;
    }
  }
  if (auto xwm = w->m_xwaylandSurface.lock()) {
    if (xwm->m_state.requestsMaximize.has_value())
      return xwm->m_state.requestsMaximize;
  }
  return std::nullopt;
}

static void setMaximized(PHLWINDOW w, bool maximized) {
  if (!w)
    return;
  auto& fs = Fullscreen::controller();
  if (!fs)
    return;
  const bool currently = fs->isFullscreen(w, Fullscreen::FSMODE_MAXIMIZED);
  if (maximized == currently)
    return;
  if (maximized)
    fs->setFullscreenMode(w, Fullscreen::FSMODE_MAXIMIZED, Fullscreen::FSMODE_MAXIMIZED, false);
  else
    fs->setFullscreenMode(w, Fullscreen::FSMODE_NONE, Fullscreen::FSMODE_NONE, false);
}

static bool isMaximizedNow(PHLWINDOW w) {
  auto& fs = Fullscreen::controller();
  return w && fs && fs->isFullscreen(w, Fullscreen::FSMODE_MAXIMIZED);
}

static bool isCoveringFullscreen(PHLWINDOW w) {
  auto& fs = Fullscreen::controller();
  return w && fs && fs->isFullscreen(w, Fullscreen::FSMODE_FULLSCREEN);
}

static CBox monitorWork(PHLWINDOW w) {
  auto mon = w->m_monitor.lock();
  if (!mon)
    return {};
  return mon->m_reservedArea.apply(CBox(mon->m_position, mon->m_size));
}

static void saveNormalFloat(PHLWINDOW w) {
  if (!w || w->isHidden())
    return;
  if (isMaximizedNow(w) || isCoveringFullscreen(w))
    return;
  const auto pos  = w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  const auto size = w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  if (size.x < 64 || size.y < 64)
    return;
  const auto work = monitorWork(w);
  if (work.w <= 0)
    return;
  if (pos.y < work.y)
    return;
  if (std::abs(size.x - work.w) <= 16 && size.y >= work.h - 48)
    return;
  g_savedFloat[reinterpret_cast<uintptr_t>(w.get())] = {pos, size};
}

static void restoreFloatOnScreen(PHLWINDOW w) {
  if (!w || w->isHidden())
    return;
  if (isMaximizedNow(w) || isCoveringFullscreen(w))
    return;
  const auto work = monitorWork(w);
  if (work.w <= 0)
    return;
  const auto key = reinterpret_cast<uintptr_t>(w.get());
  Vector2D   pos;
  Vector2D   size;
  if (auto it = g_savedFloat.find(key); it != g_savedFloat.end()) {
    pos  = it->second.pos;
    size = it->second.size;
  } else {
    pos  = w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    size = w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  }
  if (size.x > work.w)
    size.x = work.w;
  if (size.y > work.h)
    size.y = work.h;
  if (pos.x < work.x)
    pos.x = work.x;
  if (pos.y < work.y)
    pos.y = work.y;
  if (pos.x + size.x > work.x + work.w)
    pos.x = work.x + work.w - size.x;
  if (pos.y + size.y > work.y + work.h)
    pos.y = work.y + work.h - size.y;
  const auto cur = w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  const auto csz = w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  if (std::abs(cur.x - pos.x) < 1 && std::abs(cur.y - pos.y) < 1 && std::abs(csz.x - size.x) < 1 && std::abs(csz.y - size.y) < 1)
    return;
  w->finishAnimation();
  w->setBox(CBox(pos, size));
}

static void applyRequestedMinimize(PHLWINDOWREF ref, std::optional<bool> want) {
  auto w = ref.lock();
  if (!w || !want.has_value())
    return;
  setMinimized(w, *want);
}

static void applyRequestedMaximize(PHLWINDOWREF ref, std::optional<bool> want) {
  auto w = ref.lock();
  if (!w || !want.has_value() || g_inPluginApply)
    return;
  // Hyprland arms this on fullscreen exit (and we arm it when clearing the
  // fake map-time MAXIMIZED). Chromium echoes set_maximized; honoring that
  // from this plugin is what aborted the compositor.
  if (w->m_suppressNextMaximize) {
    w->m_suppressNextMaximize = false;
    return;
  }
  if (!w->m_isMapped)
    return;
  if (*want && !isMaximizedNow(w))
    saveNormalFloat(w);
  if (isMaximizedNow(w) == *want) {
    if (!*want)
      restoreFloatOnScreen(w);
    return;
  }
  g_inPluginApply = true;
  w->finishAnimation();
  setMaximized(w, *want);
  g_inPluginApply = false;
  if (!*want)
    restoreFloatOnScreen(w);
}

static void applyRequestedState(PHLWINDOWREF ref) {
  auto w = ref.lock();
  if (!w)
    return;
  // CXDGToplevelResource::m_state.requests* is reset when stateChanged
  // returns. Capture here, apply on idle.
  const auto wantMin = requestedMinimized(w);
  const auto wantMax = requestedMaximized(w);
  later([ref, wantMin, wantMax]() {
    applyRequestedMinimize(ref, wantMin);
    applyRequestedMaximize(ref, wantMax);
  });
}

// Hyprland sends XDG_TOPLEVEL_STATE_MAXIMIZED on first map to suppress CSD.
// Cursor/Chromium still draw CSD (hyprbars:no_bar + wm_capabilities) and then
// treat □ as a no-op because they already think they are maximized.
static bool isCsdWindow(PHLWINDOW w) {
  if (!w || !w->m_ruleApplicator)
    return false;
  const auto& props = w->m_ruleApplicator->m_otherProps.props;
  if (!props.contains(g_nobarEffectIdx))
    return false;
  return truthy(props.at(g_nobarEffectIdx)->effect);
}

static bool coversWorkArea(PHLWINDOW w) {
  if (!w)
    return false;
  const auto work = monitorWork(w);
  if (work.w <= 0)
    return false;
  const auto pos  = w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  const auto size = w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
  return std::abs(size.x - work.w) <= 16 && size.y >= work.h - 48 && pos.x <= work.x + 8 && pos.y <= work.y + 8;
}

static void restoreCsdCaption(PHLWINDOW w);

static void applyDefaultFloat(PHLWINDOW w) {
  const auto work = monitorWork(w);
  if (work.w <= 0)
    return;
  (void)Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, w);
  Vector2D size{1200, 740};
  if (size.x > work.w)
    size.x = work.w;
  if (size.y > work.h)
    size.y = work.h;
  Vector2D pos{work.x + (work.w - size.x) / 2.0, work.y + (work.h - size.y) / 2.0};
  if (pos.x < work.x)
    pos.x = work.x;
  if (pos.y < work.y)
    pos.y = work.y;
  w->finishAnimation();
  w->setBox(CBox(pos, size));
}

// Hyprland arms FSMODE_MAXIMIZED on first map so SSD clients hide CSD. Chrome
// still draws CSD (hyprbars:no_bar) and then treats □ as restore of an
// already-max window — a no-op on a work-area-sized float. Clear that fake
// state only when we never saved a user float (real maximize saves first).
static void clearFakeMapMaximize(PHLWINDOW w) {
  if (!w || !isCsdWindow(w) || !w->m_isMapped || g_inPluginApply)
    return;
  if (!isMaximizedNow(w) && !coversWorkArea(w))
    return;
  const auto key = reinterpret_cast<uintptr_t>(w.get());
  if (g_savedFloat.contains(key))
    return;
  g_inPluginApply = true;
  w->finishAnimation();
  setMaximized(w, false);
  g_inPluginApply = false;
  w->m_suppressNextMaximize = true;
  applyDefaultFloat(w);
  restoreCsdCaption(w);
}

static void syncCsdMaximizedState(PHLWINDOW w) {
  if (!w || !isCsdWindow(w) || g_inPluginApply)
    return;
  PHLWINDOWREF ref = w;
  later([ref]() {
    auto live = ref.lock();
    if (!live || !isCsdWindow(live) || g_inPluginApply)
      return;
    auto xdg = live->m_xdgSurface.lock();
    if (!xdg)
      return;
    auto top = xdg->m_toplevel.lock();
    if (!top)
      return;
    bool actually = isMaximizedNow(live);
    if (!actually)
      live->m_suppressNextMaximize = true;
    top->setMaximized(actually);
  });
}

// Hyprland's xdg-decoration implementation always replies SERVER_SIDE.
// Chrome then must not draw caption buttons. hyprbars:no_bar hides the SSD
// bar. The three buttons on Chrome's own tab strip disappear. Tell CSD
// clients CLIENT_SIDE before the first commit, and keep answering CLIENT_SIDE
// if they set_mode again.
static void stickDecorationMode(CXDGDecoration* deco, zxdgToplevelDecorationV1Mode mode) {
  if (!deco || !deco->m_resource)
    return;
  const auto res = deco->m_resource;
  res->setSetMode([res, mode](CZxdgToplevelDecorationV1*, zxdgToplevelDecorationV1Mode) {
    res->sendConfigure(mode);
  });
  res->setUnsetMode([res, mode](CZxdgToplevelDecorationV1*) { res->sendConfigure(mode); });
  res->sendConfigure(mode);
  deco->mostRecentlySent = mode;
}

static CXDGDecoration* decoForToplevel(wl_resource* topRes) {
  if (!PROTO::xdgDecoration || !topRes)
    return nullptr;
  auto it = PROTO::xdgDecoration->m_decorations.find(topRes);
  if (it == PROTO::xdgDecoration->m_decorations.end() || !it->second)
    return nullptr;
  return it->second.get();
}

static CXDGDecoration* decoForWindow(PHLWINDOW w) {
  if (!w)
    return nullptr;
  auto xdg = w->m_xdgSurface.lock();
  if (!xdg)
    return nullptr;
  auto top = xdg->m_toplevel.lock();
  if (!top || !top->m_resource)
    return nullptr;
  return decoForToplevel(top->m_resource->resource());
}

// Hyprland answers xdg-decoration SERVER_SIDE. If a client still binds,
// stick CLIENT_SIDE so Chrome does not wait for an SSD bar we hid.
// Chrome's Ozone ShouldUseCustomFrame() is true only when the compositor
// does not advertise xdg-decoration. Hyprland always advertises it and
// answers SERVER_SIDE, so Chrome hides Aura min/max/close and waits for
// SSD. hyprbars:no_bar then deletes the only remaining chrome. Hide the
// globals so Chrome draws the three buttons on its own tab strip again.
static void hideDecorationGlobals() {
  if (PROTO::xdgDecoration)
    PROTO::xdgDecoration->removeGlobal();
  if (PROTO::serverDecorationKDE)
    PROTO::serverDecorationKDE->removeGlobal();
}

static void hookDecorationManagers() {
  if (!PROTO::xdgDecoration)
    return;
  for (auto& mgr : PROTO::xdgDecoration->m_managers) {
    if (!mgr)
      continue;
    mgr->setGetToplevelDecoration([](CZxdgDecorationManagerV1* pMgr, uint32_t id, wl_resource* toplevel) {
      PROTO::xdgDecoration->onGetDecoration(pMgr, id, toplevel);
      if (auto* deco = decoForToplevel(toplevel))
        stickDecorationMode(deco, ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE);
    });
  }
}

static void applyDecorationMode(PHLWINDOW w) {
  auto* deco = decoForWindow(w);
  if (!deco)
    return;
  if (isCsdWindow(w)) {
    stickDecorationMode(deco, ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE);
    return;
  }
  if (w->m_isMapped && !w->m_class.empty())
    stickDecorationMode(deco, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
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

// Hyprland's xdg ctor queues TILED_LEFT/RIGHT/TOP/BOTTOM plus a fake
// MAXIMIZED so SSD clients hide CSD. Chrome caches that first configure and
// then paints the fused tab strip with only ×. A second wm_capabilities
// without xdg_surface.configure is ignored. Strip the lie and configure.
static void stripTiledAndMaximized(SP<CXDGToplevelResource> top) {
  if (!top)
    return;
  auto& states = top->m_pendingApply.states;
  states.erase(std::remove_if(states.begin(), states.end(),
                              [](const auto& s) {
                                const auto v = static_cast<uint32_t>(s);
                                return v == XDG_TOPLEVEL_STATE_TILED_LEFT || v == XDG_TOPLEVEL_STATE_TILED_RIGHT ||
                                       v == XDG_TOPLEVEL_STATE_TILED_TOP || v == XDG_TOPLEVEL_STATE_TILED_BOTTOM ||
                                       v == XDG_TOPLEVEL_STATE_MAXIMIZED;
                              }),
               states.end());
}

static bool userMaximizedCsd(PHLWINDOW w) {
  if (!w)
    return false;
  const auto key = reinterpret_cast<uintptr_t>(w.get());
  return g_savedFloat.contains(key) && isMaximizedNow(w);
}

static void restoreCsdCaption(PHLWINDOW w) {
  if (!w)
    return;
  hookDecorationManagers();
  applyDecorationMode(w);
  advertiseWmCapabilities(w);
  auto xdg = w->m_xdgSurface.lock();
  if (!xdg)
    return;
  auto top = xdg->m_toplevel.lock();
  if (!top)
    return;
  if (!userMaximizedCsd(w)) {
    stripTiledAndMaximized(top);
    top->setMaximized(false);
    w->m_suppressNextMaximize = true;
  }
  xdg->scheduleConfigure();
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
      watch.xdg   = top->m_events.stateChanged.listen([ref]() { applyRequestedState(ref); });
      attached    = true;
    }
  }
  if (auto xwm = w->m_xwaylandSurface.lock()) {
    watch.xwm  = xwm->m_events.stateChanged.listen([ref]() { applyRequestedState(ref); });
    attached   = true;
  }
  watch.resize = w->m_events.resize.listen([ref]() { saveNormalFloat(ref.lock()); });
  g_watches.insert_or_assign(key, std::move(watch));
  (void)attached;

  // Chromium caches the first wm_capabilities + decoration mode. Advertise
  // min/max and keep CLIENT_SIDE. Do not flood configure on every rule update.
  restoreCsdCaption(w);
  syncCsdMaximizedState(w);
}

static void onCsdMapped(PHLWINDOW w) {
  watchWindow(w);
  PHLWINDOWREF mapped = w;
  later([mapped]() { clearFakeMapMaximize(mapped.lock()); });
}

static void watchAllWindows() {
  for (auto& w : Desktop::windowState()->windows())
    onCsdMapped(w);
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

  g_nobarEffectIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");

  g_onCreate = Event::bus()->m_events.window.create.listen([](PHLWINDOW w) { onCsdMapped(w); });
  g_onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { onCsdMapped(w); });
  g_onOpenLate = Event::bus()->m_events.window.openLate.listen([](PHLWINDOW w) { onCsdMapped(w); });
  g_onDestroy  = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF w) {
    if (auto live = w.lock()) {
      const auto key = reinterpret_cast<uintptr_t>(live.get());
      g_watches.erase(key);
      g_savedFloat.erase(key);
    }
  });
  g_onFullscreen = Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW w) {
    syncCsdMaximizedState(w);
    PHLWINDOWREF ref = w;
    later([ref]() {
      auto live = ref.lock();
      if (live && !isMaximizedNow(live) && !isCoveringFullscreen(live))
        restoreFloatOnScreen(live);
    });
  });
  g_onUpdateRules = Event::bus()->m_events.window.updateRules.listen([](PHLWINDOW w) { watchWindow(w); });
  hideDecorationGlobals();
  hookDecorationManagers();
  later([]() { hookDecorationManagers(); });
  watchAllWindows();

  return {"omarchy-minimize", "In-place native minimize via CWindow::setHidden", "Omarchy Ultimate", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
  g_watches.clear();
  g_savedFloat.clear();
  g_onCreate      = {};
  g_onOpen        = {};
  g_onOpenLate    = {};
  g_onDestroy     = {};
  g_onFullscreen  = {};
  g_onUpdateRules = {};
}
