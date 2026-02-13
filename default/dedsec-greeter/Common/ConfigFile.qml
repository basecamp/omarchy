import Quickshell.Io
import QtQuick

Item {
    id: root
    required property string fileName
    property string profilesKey
    property string currentProfile

    FileView {
        id: jsonFile
        path: `/etc/dedsec/${root.fileName}.config.json`
        blockLoading: true
    }

    Logger {
        id: logger
        name: "Config"
    }

    readonly property var config: {
        try {
            return JSON.parse(jsonFile.text());
        } catch (e) {
            logger.critical(e);
        }
    }

    function _findValue(key) {
        if (!key || !config) {
            return null;
        }

        const keys = key.split('.');

        let value = config;

        for (key of keys) {
            if (value[key] !== undefined) {
                value = value[key];
            } else {
                return null;
            }
        }

        return value;
    }

    function _get(key: string, fallback: var, flags: var): var {
        const {
            // don't search for profile/mode overrides
            overrideable = true
        } = flags;

        let rootValue = _findValue(key);

        if (!root.profilesKey || !root.currentProfile) {
            logger.critical("profilesKey and currentProfile must be set to use this method.");
            return;
        }

        if (overrideable) {
            const profileSpecificKey = `${root.profilesKey}.${root.currentProfile}.${key}`;
            let profileSpecificValue = _findValue(profileSpecificKey);

            if (Utils.isStrictObject(profileSpecificValue)) {
                profileSpecificValue = Object.assign({}, fallback, profileSpecificValue);
            }

            if (profileSpecificValue) {
                logger.debug(`${root.fileName}.${key} : ${rootValue ? `${Utils.toStringTyped(rootValue)} ->` : ""} ${Utils.toStringTyped(profileSpecificValue)} (${root.currentProfile}.${key})`);
                return profileSpecificValue;
            }
        }

        if (rootValue) {
            logger.debug(`${root.fileName}.${key} : ${Utils.toStringTyped(rootValue)}`);

            if (Utils.isStrictObject(rootValue)) {
                rootValue = Object.assign({}, fallback, rootValue);
            }

            return rootValue;
        }

        logger.debug(`${root.fileName}.${key} : ${Utils.toStringTyped(fallback)} (default)`);
        return fallback;
    }

    function getOptional(key: string, fallback, flags = {}): var {
        return _get(key, fallback, flags);
    }

    function getRequired(key: string, flags = {}): var {
        const value = _get(key, null, flags);

        if (value === undefined || value === null) {
            logger.critical(`Missing required: ${root.fileName}.` + key);
            return;
        }

        return value;
    }
}
