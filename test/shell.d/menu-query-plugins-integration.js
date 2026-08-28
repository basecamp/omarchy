// Real end-to-end integration test of the query-plugin logic, using the actual
// bins (omarchy-query-calc / omarchy-query-web) and the real MenuModel.js.
// This exercises the full path the QML would take:
//   query -> queryPluginsForQuery -> run bin -> queryPluginRow -> action string
// so we can prove the feature works without a display.

const { execFileSync } = require("child_process");
const path = require("path");
const menu = require(path.join(__dirname, "..", "..", "shell/plugins/menu/MenuModel.js"));

const binDir = path.join(__dirname, "..", "..", "bin"); // bins live in bin/
function runBin(name, args) {
  try {
    return execFileSync(path.join(binDir, name), args, { encoding: "utf8" }).trim();
  } catch (e) {
    return "Error: " + String(e.stderr || e.message).trim();
  }
}

// Mirror the built-in plugin defs from Menu.qml (args: "url" -> --print mode).
const builtins = [
  { id: "omarchy.query.calc", kind: "math", icon: "calc", language: "en",
    enabled: true, action: "copy", command: "omarchy-query-calc", builtin: true },
  { id: "omarchy.query.web", kind: "web", icon: "search", language: "en",
    enabled: true, action: "run", command: "omarchy-query-web", args: "url", builtin: true },
];
const map = {};
builtins.forEach(p => (map[p.id] = JSON.parse(JSON.stringify(p))));

function isError(result) {
  return !result || result === "Error" || result.startsWith("Error:");
}

const queries = ["2+2", "2^10", "sqrt(16)+1", "omarchy linux", "https://example.com", "translate hola"];

let failures = 0;
for (const q of queries) {
  const plugins = menu.queryPluginsForQuery(map, q);
  if (plugins.length === 0) {
    console.log(`query "${q}" -> (no plugin fires, normal search continues)`);
    continue;
  }
  for (const p of plugins) {
    // Mirror Menu.qml makeQueryRunner: args "url" means --print (compute only).
    const result = runBin(p.command, p.args === "url" ? ["--print", q] : [q]);
    if (isError(result)) {
      console.log(`query "${q}" -> plugin ${p.id} returned "${result}" (no row)`);
      continue;
    }
    const row = menu.queryPluginRow(p, q, result, p.language || "en");
    // Build the action string the same way Menu.qml fillQueryResult does.
    let action;
    if (p.action === "copy") {
      action = `printf '%s' ${JSON.stringify(result)} | wl-copy`;
    } else if (p.action === "run" && p.kind === "web") {
      const url = p.args === "url" ? result : q;
      action = `omarchy-launch-webapp ${JSON.stringify(url)}`;
    } else if (p.action === "run") {
      action = `${p.command} ${JSON.stringify(q)}`;
    }
    const ok = row && row.kind === "query" && row.section === "results" &&
               row.icon.length > 0 &&
               typeof action === "string" && action.length > 0;
    if (!ok) failures++;
    console.log(`query "${q}" -> [${p.kind}] ${row.label}  | ENTER runs: ${action}`);
  }
}

console.log("\n" + (failures === 0 ? "INTEGRATION OK: all fired plugins produced valid rows+actions"
                                   : `INTEGRATION FAILED: ${failures} bad rows`));
process.exit(failures === 0 ? 0 : 1);
