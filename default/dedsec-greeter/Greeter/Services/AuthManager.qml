pragma Singleton

import Quickshell
import QtQuick

import "../Config"
import "../Common"

Singleton {
    id: authManager

    Logger {
        id: logger
        name: "AuthManager"
    }

    enum State {
        // waiting for handler to be ready
        Inactive,

        // main states
        Ready,
        Loading,
        Failed,
        Success,

        // quit and grant access
        Finish
    }

    property string user: Settings.user

    property int state: AuthManager.State.Inactive

    property var _handler

    property bool _firstSession: true

    readonly property string _dedsecPrefix: "[DEDSEC]"
    readonly property string _profilerPrefix: "[PROFILER]"

    Component.onCompleted: {
        if (Settings.isTest) {
            _handler = FakeHandler;
            TerminalManager.displayMessage(`◈ ${authManager._dedsecPrefix} Using Protocol::TEST`);
        } else if (Settings.isGreetd) {
            _handler = GreetdHandler;
            TerminalManager.displayMessage(`${authManager._dedsecPrefix} Protocol::DEDSEC_GREETD->Init`);
        } else if (Settings.isLockd) {
            _handler = LockdHandler;
            TerminalManager.displayMessage(`${authManager._dedsecPrefix} Protocol::DEDSEC_LOCKD->Init`);
        } else {
            throw new Error("No Auth Manager provided: set DEDSEC_MODE to 'greetd' or 'lockd'");
        }

        _handler.ready.connect(onReady);
        _handler.success.connect(onSuccess);
        _handler.failed.connect(onFailed);

        _handler.start();

        TerminalManager.displayMessage(`${_profilerPrefix} CIPHER_NEGOTIATED <-> bnet://0x8D2A4F1B:1443`);
    }

    function onReady() {
        authManager.state = AuthManager.State.Ready;

        if (authManager._firstSession) {
            TerminalManager.displayMessage(`${authManager._dedsecPrefix} Opened session for user(${authManager.user})`);
            authManager._firstSession = false;
        } else {
            TerminalManager.displayMessage(`${authManager._dedsecPrefix} Session recreated with existing parameters.`);
        }
    }

    function onSuccess() {
        authManager.state = AuthManager.State.Success;
        TerminalManager.displayMessage(`${authManager._dedsecPrefix} IDENTITY_VERIFIED // WELCOME BACK`);
        TerminalManager.displayMessage(`${authManager._dedsecPrefix} Session closed for user(${authManager.user.toUpperCase()})`);
    }

    function onFailed() {
        authManager.state = AuthManager.State.Failed;
        TerminalManager.displayMessage(`${authManager._profilerPrefix} Authentication Failed (TraceId: ${Faker.randomHexString(16)})`);

        startTimer.start();
    }

    Timer {
        id: startTimer
        interval: 500
        onTriggered: {
            authManager._handler.start();
        }
    }

    function respond(password: string) {
        if (authManager.state !== AuthManager.State.Ready) {
            logger.error("Auth Manager not ready, response discarded.");
            return;
        }

        authManager.state = AuthManager.State.Loading;

        loadTimer.password = password;
        loadTimer.start();
    }

    Timer {
        id: loadTimer
        interval: 1000
        property string password: ""
        onTriggered: {
            authManager._handler.respond(loadTimer.password);
        }
    }

    function finish() {
        authManager.state = AuthManager.State.Finish;
        authManager._handler.finish();
    }
}
