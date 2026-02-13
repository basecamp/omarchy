pragma Singleton

import QtQuick
import Quickshell

Singleton {
    Logger {
        id: logger
        name: "Env"
    }

    function get(name: string): var {
        return Quickshell.env(`DEDSEC_${name}`);
    }

    function log(name: string, value: var, isDefault = false): void {
        logger.debug(`Env.DEDSEC_${name} = ${Utils.toStringTyped(value)}${isDefault ? " (Default)" : ""}`);
    }

    function processArray(raw: string): var {
        try {
            const components = raw.split(",").map(s => s.trim()).filter(s => s.length > 0);
            return {
                isSuccess: true,
                array: components
            };
        } catch (error) {
            logger.error(error);
            return {
                isSuccess: false,
                array: []
            };
        }
    }

    function getArray(name: string, fallback = []): var {
        const value = get(name);

        if (!value) {
            log(name, fallback, true);
            return fallback;
        }

        const result = processArray(value);

        if (!result.isSuccess) {
            logger.error(`Env.DEDSEC_${name} is invalid. Form must be DEDSEC_${name}=arg1,arg2,...`);
            return fallback;
        }

        log(name, result.array);
        return result.array;
    }
}
