pragma Singleton

import Quickshell

Singleton {
    function randomHexString(size = 8) {
        return [...Array(size)].map(() => Math.floor(Math.random() * 16).toString(16).toUpperCase()).join('');
    }
}
