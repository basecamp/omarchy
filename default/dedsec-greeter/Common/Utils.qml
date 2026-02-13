pragma Singleton

import Quickshell

Singleton {
    function padTime(n: int): string {
        return n.toString().padStart(2, "0");
    }

    function getTimestamp(): string {
        const date = new Date();
        return padTime(date.getHours()) + ":" + padTime(date.getMinutes()) + ":" + padTime(date.getSeconds());
    }

    function clamp(num: int, min: int, max: int): int {
        return Math.round(Math.min(Math.max(num, min), max));
    }

    function toStringTyped(value: var): string {
        let valueString;
        if (value === null || value === undefined) {
            valueString = String(value);
        } else if (typeof value === "string") {
            valueString = `'${value}'`;
        } else if (Number.isInteger(value)) {
            valueString = value;
        } else if (Array.isArray(value)) {
            valueString = `[${value}]`;
        } else if (typeof value === "object") {
            try { valueString = JSON.stringify(value, null, 2); }
            catch(e) { valueString = String(value); }
        } else {
            valueString = String(value);
        }

        return valueString;
    }

    /* Detect POJO */
    function isStrictObject(value) {
        return (typeof value === 'object' && value !== null && !Array.isArray(value) && value.constructor === Object);
    }
}
