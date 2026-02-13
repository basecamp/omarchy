pragma Singleton

import QtQuick
import Quickshell

import "../Common"
import "../Config"

Singleton {
    id: terminalManager

    property var _queue: []

    property var logModel: ListModel {}

    signal paused(string pauseMarker)

    property string pauseMarker

    Timer {
        id: worker
        repeat: true
        onTriggered: () => {
            if (terminalManager._queue.length === 0) {
                worker.stop();
                return;
            }

            const item = terminalManager._queue.shift();

            terminalManager._addToModel(item);

            if (item.pauseWithMarker) {
                worker.stop();
                terminalManager.paused(item.pauseWithMarker);

                return;
            }

            const minDelay = 200;
            const maxDelay = 500;
            const delay = Math.random() * maxDelay;
            worker.interval = Utils.clamp(delay, minDelay, maxDelay);
        }
    }

    function _addToModel(item) {
        logModel.append(item);

        if (logModel.count > 50) {
            logModel.remove(0);
        }
    }

    function notifyReady() {
        if (!worker.running) {
            worker.start();
        }
    }

    function displayMessage(message: string, pauseWithMarker = "") {
        const item = {
            message,
            pauseWithMarker
        };

        terminalManager._queue.push(item);

        if (!worker.running) {
            worker.start();
        }
    }

    property bool isPaused: false

    function unPause() {
        isPaused = false;
        worker.start();
    }

    Component.onCompleted: {
        displayMessage("REGION_LINK_ESTABLISHED : AU-SOUTH-EAST-2");
        displayMessage("LOG_STREAM_CONNECTED // 1B7C5296-469D-4595-AD5D-4E31349CF13F");

        displayMessage(`WL_OUTPUT_FOUND: ${Settings.monitor} <-> ADDR_PTR: 0x${Faker.randomHexString()}`);
        displayMessage("---GREETER_UI_INITIALIZING---", "UI_INIT");
    }
}
