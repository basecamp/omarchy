pragma Singleton

import Quickshell
import Quickshell.Services.Greetd
import QtQuick

import "../Config"
import "../Common"

Singleton {
    id: handler

    signal ready
    signal success
    signal failed

    Logger {
        id: logger
        name: "Greetd"
    }

    Connections {
        id: connection
        target: Greetd

        function onAuthMessage(message) {
            // requesting password
            logger.info("Credentials requested...");
            handler.ready();
        }

        function onAuthFailure(message) {
            // password is wrong
            logger.info("// AUTH_ERROR");
            handler.failed();
        }

        function onReadyToLaunch() {
            // password is correct
            handler.success();
        }
    }

    function start() {
        sessionStarter.start();
    }

    Timer {
        id: sessionStarter
        interval: 200
        repeat: true
        onTriggered: {
            // make sure socket ready for new session
            // authenticating(1) -> inactive (0)
            if (Greetd.state !== GreetdState.Inactive) {
                return;
            }

            logger.info(`Initializing session...(user:${AuthManager.user})`);
            Greetd.createSession(AuthManager.user);

            sessionStarter.stop();
        }
    }

    function respond(password) {
        if (Greetd.available) {
            Greetd.respond(password);
        } else {
            logger.debug("Failed to respond, Not available.");
        }
    }

    function finish() {
        logger.info(`Launching: ${Settings.launchCommand.join(" ")}`);

        Greetd.launch(Settings.launchCommand);
        Quickshell.execDetached(Settings.exitCommand);
    }
}
