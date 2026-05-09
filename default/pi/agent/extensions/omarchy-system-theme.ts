/**
 * Syncs pi's light/dark theme with the active Omarchy theme.
 *
 * Omarchy light themes include:
 *   ~/.config/omarchy/current/theme/light.mode
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = process.env.HOME ?? "";
const lightModePath = join(home, ".config/omarchy/current/theme/light.mode");

function omarchyPiTheme(): "light" | "dark" {
	return existsSync(lightModePath) ? "light" : "dark";
}

export default function (pi: ExtensionAPI) {
	let intervalId: ReturnType<typeof setInterval> | null = null;

	pi.on("session_start", (_event, ctx) => {
		let currentTheme = omarchyPiTheme();
		ctx.ui.setTheme(currentTheme);

		intervalId = setInterval(() => {
			const nextTheme = omarchyPiTheme();
			if (nextTheme !== currentTheme) {
				currentTheme = nextTheme;
				ctx.ui.setTheme(currentTheme);
			}
		}, 2000);
	});

	pi.on("session_shutdown", () => {
		if (intervalId) {
			clearInterval(intervalId);
			intervalId = null;
		}
	});
}
