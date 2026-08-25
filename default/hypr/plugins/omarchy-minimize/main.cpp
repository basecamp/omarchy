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
#define private public
#include "src/Compositor.hpp"
#undef private
#include "xdg-shell.hpp"

#include <wayland-server.h>
#include <wayland-server-core.h>

#include <algorithm>
#include <cctype>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <format>
#include <functional>
#include <iterator>
#include <optional>
#include <regex>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>
#include <unordered_map>
#include <vector>

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

  // Popin/slide mid-hide leaves the client at an interpolated box off the
  // work area. The caption is then undraggable.
  w->finishAnimation();
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

static void restoreCsdCaption(PHLWINDOW w);
static bool isCsdWindow(PHLWINDOW w);

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
  // hyprbars draws 32px above the client box. Parking SSD at work.y puts
  // min/max/close above the monitor.
  const double bar = isCsdWindow(w) ? 0.0 : 32.0;
  if (pos.x < work.x)
    pos.x = work.x;
  if (pos.y < work.y + bar)
    pos.y = work.y + bar;
  if (pos.x + size.x > work.x + work.w)
    pos.x = work.x + work.w - size.x;
  if (pos.y + size.y > work.y + work.h)
    pos.y = work.y + work.h - size.y;
  if (pos.y < work.y + bar)
    pos.y = work.y + bar;
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
    // Hyprland's own handler may already have maxed the surface. Still tell
    // Chrome so it relayouts the CSD frame to the work area.
    if (isMaximizedNow(w) || isCoveringFullscreen(w))
      restoreCsdCaption(w);
    return;
  }
  if (!w->m_isMapped)
    return;
  if (*want && !isMaximizedNow(w))
    saveNormalFloat(w);
  if (isMaximizedNow(w) == *want) {
    if (!*want)
      restoreFloatOnScreen(w);
    else
      restoreCsdCaption(w);
    return;
  }
  g_inPluginApply = true;
  w->finishAnimation();
  setMaximized(w, *want);
  g_inPluginApply = false;
  if (!*want) {
    restoreFloatOnScreen(w);
    w->m_suppressNextMaximize = true;
  }
  restoreCsdCaption(w);
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
    bool actually = isMaximizedNow(live) || isCoveringFullscreen(live);
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

// Chrome Ozone ShouldUseCustomFrame() is true only when this client does
// not see zxdg_decoration_manager_v1. Hyprland advertises it and answers
// SERVER_SIDE, so Chrome hides Aura min/max/close and waits for SSD.
// hyprbars:no_bar then deletes the only remaining chrome.
//
// removeGlobal() hid the manager from every client. Foot then logged
// "no decoration manager — using CSDs" and hyprbars never attached.
// Filter the two decoration globals per client instead: CSD processes
// (Chrome, Files, Cursor) do not see them; SSD clients still do.
static std::vector<std::regex> g_csdClassRegexes;
static bool g_csdClassPatternsLoaded = false;

static std::string csdClientsJsonPath() {
  const char* omarchy = std::getenv("OMARCHY_PATH");
  if (omarchy && *omarchy) {
    std::string path = std::string(omarchy) + "/default/ultimate/csd-clients.json";
    if (std::ifstream{path})
      return path;
  }
  if (std::ifstream in{"/usr/share/omarchy/default/ultimate/csd-clients.json"})
    return "/usr/share/omarchy/default/ultimate/csd-clients.json";
  return "";
}

static std::string unescapeJsonString(const std::string& raw) {
  std::string out;
  out.reserve(raw.size());
  for (size_t i = 0; i < raw.size(); ++i) {
    if (raw[i] == '\\' && i + 1 < raw.size()) {
      out.push_back(raw[++i]);
      continue;
    }
    out.push_back(raw[i]);
  }
  return out;
}

static void loadCsdClassPatterns() {
  if (g_csdClassPatternsLoaded)
    return;
  g_csdClassPatternsLoaded = true;
  const auto path = csdClientsJsonPath();
  if (path.empty())
    return;
  std::ifstream in{path};
  if (!in)
    return;
  const std::string body((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  const auto key = body.find("classPatterns");
  if (key == std::string::npos)
    return;
  const auto start = body.find('[', key);
  const auto stop = body.find(']', start);
  if (start == std::string::npos || stop == std::string::npos)
    return;
  const auto slice = body.substr(start, stop - start);
  const std::regex quoted{"\"((?:[^\"\\\\]|\\\\.)*)\""};
  for (std::sregex_iterator it{slice.begin(), slice.end(), quoted}, end; it != end; ++it) {
    const auto pat = unescapeJsonString((*it)[1].str());
    if (pat.empty())
      continue;
    try {
      g_csdClassRegexes.emplace_back(pat, std::regex::icase | std::regex::ECMAScript);
    } catch (const std::regex_error&) {
    }
  }
}

static bool nameLooksCsd(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (s.find("zenity") != std::string::npos)
    return false;
  loadCsdClassPatterns();
  std::string base = s;
  const auto slash = s.find_last_of('/');
  if (slash != std::string::npos)
    base = s.substr(slash + 1);
  for (const auto& re : g_csdClassRegexes) {
    if (std::regex_search(s, re) || std::regex_search(base, re))
      return true;
  }
  return false;
}

static bool clientLooksCsd(const wl_client* client) {
  pid_t pid = 0;
  uid_t uid = 0;
  gid_t gid = 0;
  wl_client_get_credentials(const_cast<wl_client*>(client), &pid, &uid, &gid);
  if (pid <= 0)
    return false;
  std::string comm;
  if (std::ifstream in{std::format("/proc/{}/comm", pid)})
    std::getline(in, comm);
  char exe[PATH_MAX]{};
  const auto n = readlink(std::format("/proc/{}/exe", pid).c_str(), exe, sizeof(exe) - 1);
  const std::string exePath = n > 0 ? std::string(exe, static_cast<size_t>(n)) : "";
  return nameLooksCsd(comm) || nameLooksCsd(exePath);
}

static bool isDecorationGlobal(const wl_global* global) {
  const auto* iface = wl_global_get_interface(global);
  if (!iface || !iface->name)
    return false;
  const std::string_view name{iface->name};
  return name == "zxdg_decoration_manager_v1" || name == "org_kde_kwin_server_decoration_manager";
}

static bool decorationGlobalFilter(const wl_client* client, const wl_global* global, void*) {
  if (isDecorationGlobal(global) && clientLooksCsd(client))
    return false;
  return true;
}

static void hideDecorationGlobals() {
  if (g_pCompositor && g_pCompositor->m_wlDisplay)
    wl_display_set_global_filter(g_pCompositor->m_wlDisplay, decorationGlobalFilter, nullptr);
}

static PHLWINDOW windowForToplevel(wl_resource* topRes) {
  if (!topRes)
    return nullptr;
  for (auto& w : Desktop::windowState()->windows()) {
    if (!w)
      continue;
    auto xdg = w->m_xdgSurface.lock();
    if (!xdg)
      continue;
    auto top = xdg->m_toplevel.lock();
    if (top && top->m_resource && top->m_resource->resource() == topRes)
      return w;
  }
  return nullptr;
}

static void hookDecorationManagers() {
  if (!PROTO::xdgDecoration)
    return;
  for (auto& mgr : PROTO::xdgDecoration->m_managers) {
    if (!mgr)
      continue;
    mgr->setGetToplevelDecoration([](CZxdgDecorationManagerV1* pMgr, uint32_t id, wl_resource* toplevel) {
      PROTO::xdgDecoration->onGetDecoration(pMgr, id, toplevel);
      auto* deco = decoForToplevel(toplevel);
      if (!deco)
        return;
      auto w = windowForToplevel(toplevel);
      // CSD clients that still bind must get CLIENT_SIDE first. SSD clients
      // (foot) must keep SERVER_SIDE so they do not invent a second chrome.
      const auto mode = (w && isCsdWindow(w)) ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE
                                              : ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
      stickDecorationMode(deco, mode);
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
static void stripTiledAndMaximized(SP<CXDGToplevelResource> top, bool alsoMaximized) {
  if (!top)
    return;
  auto& states = top->m_pendingApply.states;
  states.erase(std::remove_if(states.begin(), states.end(),
                              [alsoMaximized](const auto& s) {
                                const auto v = static_cast<uint32_t>(s);
                                return v == XDG_TOPLEVEL_STATE_TILED_LEFT || v == XDG_TOPLEVEL_STATE_TILED_RIGHT ||
                                       v == XDG_TOPLEVEL_STATE_TILED_TOP || v == XDG_TOPLEVEL_STATE_TILED_BOTTOM ||
                                       (alsoMaximized && v == XDG_TOPLEVEL_STATE_MAXIMIZED);
                              }),
               states.end());
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
  // Keep MAXIMIZED in the configure when the compositor actually maximized.
  // Stripping it (and arming suppress) on every float watch ate the user's
  // CSD □ click: Hyprland grew the surface to 1920×1032, Chrome kept painting
  // a 1200px frame in the corner, and the next set_maximized was ignored.
  const bool actuallyMaxed = isMaximizedNow(w) || isCoveringFullscreen(w);
  stripTiledAndMaximized(top, !actuallyMaxed);
  top->setMaximized(actuallyMaxed);
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
  loadCsdClassPatterns();
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
