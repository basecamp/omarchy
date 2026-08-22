#define WLR_USE_UNSTABLE

#include "src/plugins/PluginAPI.hpp"
#include "src/desktop/state/FocusState.hpp"
#include "src/desktop/state/WindowState.hpp"
#include "src/desktop/view/Window.hpp"
#include "src/render/Renderer.hpp"

#include <algorithm>
#include <cctype>
#include <format>
#include <stdexcept>
#include <string>

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

  return {"omarchy-minimize", "In-place native minimize via CWindow::setHidden", "Omarchy Ultimate", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {}
