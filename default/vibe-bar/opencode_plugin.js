import { connect } from "net";
import { appendFileSync } from "fs";

const SOCKET_PATH = "/tmp/vibe-agents.sock";
const DEBUG_LOG = "/tmp/vibe-bar-opencode-debug.log";
const DEBUG = process.env.VIBE_BAR_DEBUG === "1";

function debugLog(msg) {
  if (!DEBUG) return;
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

function encodeEnvelope(event) {
  return JSON.stringify(event) + "\n";
}

function sendToSocket(json) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.end(encodeEnvelope(json));
      });
      sock.on("data", () => {});
      sock.on("end", () => { resolve(true); });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });
}

function sendAndWaitDecision(json, timeoutMs = 86400000) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.write(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => {
        buf += chunk.toString();
        if (buf.includes("\n")) {
          sock.destroy();
          try {
            resolve(JSON.parse(buf.trim()).decision || "allow");
          } catch { resolve("allow"); }
        }
      });
      sock.on("error", () => resolve("allow"));
      sock.on("end", () => resolve("allow"));
      sock.on("close", () => resolve("allow"));
      sock.setTimeout(timeoutMs, () => { sock.destroy(); resolve("allow"); });
    } catch { resolve("allow"); }
  });
}

function makePayload(hookName, sessionID, cwd, extra = {}) {
  return {
    hook_event_name: hookName,
    session_id: sessionID,
    cwd: cwd || ".",
    agent: "opencode",
    ...extra,
  };
}

export default async ({ client, serverUrl }) => {
  const sessionCwd = new Map();

  debugLog(`VibeBar plugin loaded | serverUrl=${JSON.stringify(serverUrl)}`);

  return {
    event: async ({ event }) => {
      try {
        const t = event.type;
        const p = event.properties || {};
        debugLog(`EVENT: ${t} | ${JSON.stringify(p).slice(0, 200)}`);

        if (t === "session.created" && p.info) {
          const cwd = p.info.directory || process.cwd();
          sessionCwd.set(p.info.id, cwd);
          await sendToSocket(makePayload("SessionStart", p.info.id, cwd));
        }
        else if (t === "session.updated" && p.info?.id) {
          const cwd = p.info.directory;
          if (cwd) {
            const isNew = !sessionCwd.has(p.info.id);
            sessionCwd.set(p.info.id, cwd);
            // Re-register with daemon (handles daemon restart losing state)
            if (isNew) await sendToSocket(makePayload("SessionStart", p.info.id, cwd));
          }
        }
        else if (t === "session.deleted" && p.info) {
          await sendToSocket(makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id)));
          sessionCwd.delete(p.info.id);
        }
        else if (t === "session.status" && p.sessionID) {
          const status = p.status?.type;
          if (status === "idle") {
            await sendToSocket(makePayload("Stop", p.sessionID, sessionCwd.get(p.sessionID)));
          } else if (status === "busy") {
            // Wakes up Waybar when user sends a message; also re-registers after daemon restart
            const cwd = sessionCwd.get(p.sessionID) || process.cwd();
            await sendToSocket(makePayload("UserPromptSubmit", p.sessionID, cwd));
          }
        }
        else if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
          const st = p.part.state?.status;
          const cwd = sessionCwd.get(p.part.sessionID);
          const toolName = (p.part.tool || "unknown").charAt(0).toUpperCase() + (p.part.tool || "").slice(1);

          if (st === "running" || st === "pending") {
            await sendToSocket(makePayload("PreToolUse", p.part.sessionID, cwd, { tool_name: toolName }));
          } else if (st === "completed" || st === "error") {
            await sendToSocket(makePayload("PostToolUse", p.part.sessionID, cwd, { tool_name: toolName }));
          }
        }
        else if (t === "permission.asked" && p.id && p.sessionID) {
          const toolName = (p.permission || "unknown").charAt(0).toUpperCase() + (p.permission || "").slice(1);
          const patterns = p.patterns || [];
          const toolInput = { patterns };
          if (p.permission === "bash" && patterns.length > 0) toolInput.command = patterns.join(" && ");
          else if ((p.permission === "edit" || p.permission === "write") && patterns.length > 0) toolInput.file_path = patterns[0];

          const payload = makePayload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
            tool_name: toolName,
            tool_input: toolInput,
          });

          // Non-blocking: don't freeze OpenCode's event loop
          sendAndWaitDecision(payload).then(async (decision) => {
            const response = decision === "allow" ? "once" : "reject";
            try {
              await client.postSessionIdPermissionsPermissionId({
                path: { id: p.sessionID, permissionID: p.id },
                body: { response },
              });
              debugLog(`Permission ${p.id} replied: ${response}`);
            } catch (e) { debugLog(`Failed to reply to permission: ${e}`); }
          });
        }
        else if (t === "permission.replied" && p.sessionID) {
          await sendToSocket(makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID)));
        }
      } catch (e) {
        debugLog(`ERROR: ${e}`);
      }
    }
  };
};
