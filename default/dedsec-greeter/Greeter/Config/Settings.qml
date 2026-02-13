pragma Singleton

import QtQuick
import Quickshell

import "../Common"

Singleton {
    id: root

    ConfigFile {
        id: greeter
        fileName: "greeter"
        profilesKey: "modes"
        currentProfile: Object.keys(root.modes).find(key => root.modes[key] === root.mode)
    }

    Logger {
        id: logger
        name: "settings"
    }

    readonly property var modes: {
        "test": 0,
        "lockd": 1,
        "greetd": 2
    }

    readonly property int mode: {
        const key = (Env.get("MODE") || "").toLowerCase();

        if (modes.hasOwnProperty(key)) {
            Env.log("MODE", key);
            return modes[key];
        }

        Env.log("MODE", "test", true);
        return modes.test;
    }

    readonly property bool isDebug: {
        const value = Env.get("DEBUG");
        Env.log("DEBUG", value || 0);
        return value === "1";
    }

    readonly property bool isTest: mode === modes.test
    readonly property bool isGreetd: mode === modes.greetd
    readonly property bool isLockd: mode === modes.lockd

    readonly property string monitor: {
        const monitor = greeter.getOptional("monitor");

        const defaultMonitor = Quickshell.screens[0].name;

        if (!monitor) {
            return defaultMonitor;
        }

        const screen = Quickshell.screens.find(screen => screen.name === monitor);

        if (!screen) {
            return defaultMonitor;
        }

        return monitor;
    }

    readonly property string user: greeter.getRequired("user").toString()

    enum AnimationMode {
        None = 0,
        Reduced = 1,
        All = 2
    }

    readonly property int animationMode: {
        const value = greeter.getOptional("animations", "all");

        switch (value.toLowerCase()) {
        case "none":
            logger.critical("Animation Mode: None not supported currently.");
            return Settings.AnimationMode.None;
        case "reduced":
            return Settings.AnimationMode.Reduced;
        case "all":
            return Settings.AnimationMode.All;
        default:
            return Settings.AnimationMode.All;
        }
    }

    function animationProfile(mode: int): bool {
        return animationMode >= mode;
    }

    readonly property var launchCommand: greeter.getOptional("modes.greetd.launch", ["uwsm", "start", "hyprland.desktop"], {
        overrideable: false
    })
    readonly property var exitCommand: greeter.getOptional("modes.greetd.exit", ["uwsm", "stop"], {
        overrideable: false
    })

    readonly property var identity: greeter.getOptional("identity", {
        "id": "OPR-000",
        "class": "SEC_OPS",
        "fullName": root.user.toUpperCase()
    })

    readonly property var systemInfo: greeter.getOptional("systemInfo", {
        "env": "Workstation",
        "node": "localhost"
    })

    readonly property string fontFamily: greeter.getOptional("fontFamily", Theme.fontFamily)
}
