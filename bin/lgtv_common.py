#!/usr/bin/env python3
"""
Common utilities for LG TV WebSocket communication.

This module provides shared functionality for LG TV control scripts:
- WebSocket client with SSL support for LG's self-signed certificates
- Retry logic for transient SSL errors after TV idle/reboot
- Configuration loading from ~/.config/lgtv/config.json
- Notification helpers

Design notes (DO NOT REMOVE without understanding):
- RETRY LOGIC: LG TV's WebSocket service returns transient SSL errors
  (SSL: UNEXPECTED_MESSAGE, SSL: UNEXPECTED_EOF_WHILE_READING) after PC reboot
  or period of inactivity. Retrying 2-3 times with delays resolves this.
- NEW CLIENT PER ATTEMPT: WebSocket connection closes after each operation.
  Cannot reuse LGTVClient instance - must create fresh one for retries.
- SOCKET TIMEOUT: ws4py library has no connection timeout. After TV idle period,
  connect() can hang for 15+ seconds. We set socket.setdefaulttimeout() before
  connecting to fail fast and let retry logic handle it.
"""
import copy
import json
import os
import socket
import ssl
import subprocess
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable

from ws4py.client.threadedclient import WebSocketClient
from LGTV.payload import hello_data

# =============================================================================
# Configuration
# =============================================================================
CONFIG_PATH = Path.home() / ".config/lgtv/config.json"

# Fallback TV names when multiple TVs configured
FALLBACK_TV_NAMES = ["MyTV", "default", "LG TV"]

# =============================================================================
# Timing constants
# =============================================================================
CONNECT_TIMEOUT = 2
POLL_INTERVAL = 0.05
SUBPROCESS_TIMEOUT = 5

# Retry settings for transient SSL errors (see module docstring for rationale)
RETRY_ATTEMPTS = 3
RETRY_DELAY = 0.5  # Multiplied by attempt number for increasing backoff
SLOW_CONNECT_THRESHOLD = 1.0  # Show "Connecting..." notification after this delay

# =============================================================================
# Network
# =============================================================================
LGTV_SSL_PORT = 3001
SOCKET_TIMEOUT = 3  # Timeout for socket connect (ws4py has no built-in timeout)

# Transient errors that warrant retry (see module docstring for rationale)
RETRYABLE_ERRORS = ("SSL", "Connection", "EOF", "timed out")

# Brightness cache - shared because picture-mode needs to invalidate it
# when mode changes (each picture mode has its own brightness on LG TVs)
BRIGHTNESS_CACHE_PATH = Path.home() / ".cache/lgtv-brightness"


# =============================================================================
# Helper functions
# =============================================================================
def run_cmd(args: list[str]) -> None:
    """Run subprocess with standard options (fire-and-forget, no output)."""
    subprocess.run(args, capture_output=True, timeout=SUBPROCESS_TIMEOUT)


def notify(title: str, message: str, urgency: str = "normal", timeout_ms: int = 2000,
           icon: str | None = None) -> None:
    """Show desktop notification."""
    args = ["notify-send", "-u", urgency, "-t", str(timeout_ms)]
    if icon:
        args.extend(["-i", icon])
    args.extend([title, message])
    run_cmd(args)


def load_config() -> tuple[str, str]:
    """
    Load TV IP and key from config.

    Uses LGTV_NAME env var if set, otherwise falls back to common TV names
    or the first TV found in config.

    Returns:
        Tuple of (ip, key) for the TV.

    Raises:
        FileNotFoundError: If config file doesn't exist.
        KeyError: If specified TV not found or multiple TVs without LGTV_NAME.
    """
    with open(CONFIG_PATH) as f:
        config = json.load(f)

    tv_name = os.environ.get("LGTV_NAME")
    if tv_name:
        if tv_name not in config:
            raise KeyError(f"TV '{tv_name}' not found in config")
        tv = config[tv_name]
    elif len(config) == 1:
        tv = next(iter(config.values()))
    else:
        # Multiple TVs, try common names
        for name in FALLBACK_TV_NAMES:
            if name in config:
                tv = config[name]
                break
        else:
            raise KeyError(f"Multiple TVs found, set LGTV_NAME env var: {list(config.keys())}")

    return tv["ip"], tv["key"]


def is_retryable(error: str | None) -> bool:
    """Check if error is transient and warrants retry."""
    return error is not None and any(x in str(error) for x in RETRYABLE_ERRORS)


def invalidate_brightness_cache() -> None:
    """
    Delete brightness cache.

    Called by picture-mode script when mode changes, because each
    picture mode on LG TVs has its own brightness setting.
    """
    try:
        BRIGHTNESS_CACHE_PATH.unlink(missing_ok=True)
    except OSError:
        pass


def load_config_or_notify(title: str) -> tuple[str, str] | None:
    """Load TV config, showing notification on failure. Returns (ip, key) or None."""
    try:
        return load_config()
    except (FileNotFoundError, KeyError) as e:
        notify(title, f"Config error: {e}", "critical")
        return None


def make_retry_notifier(title: str) -> Callable[[int], None]:
    """
    Create a retry notification callback for use with with_retry().

    Args:
        title: Notification title (e.g., "TV Brightness").

    Returns:
        Callback function that shows "Reconnecting..." notification.
    """
    def notify_retry(attempt: int) -> None:
        notify(title, f"Reconnecting to TV... (attempt {attempt + 1}/{RETRY_ATTEMPTS})",
               urgency="low", timeout_ms=1500)
    return notify_retry


# =============================================================================
# WebSocket Client
# =============================================================================
class LGTVClient(WebSocketClient):
    """
    WebSocket client for LG TV communication.

    Handles SSL setup, registration handshake, and command execution.
    Each instance is single-use - create a new one for each operation.
    """

    def __init__(self, ip: str, key: str):
        self._client_key = key
        self.result: dict | None = None
        self.error: str | None = None
        self.command_done = False
        self.pending_command: dict | None = None

        # LG TV uses self-signed certificate - must disable verification
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        super().__init__(
            f'wss://{ip}:{LGTV_SSL_PORT}/',
            exclude_headers=["Origin"],
            ssl_options={"context": ssl_context}
        )

    def opened(self) -> None:
        """Send registration message when connection opens."""
        hello = copy.deepcopy(hello_data)
        hello["type"] = "register"
        hello["payload"]["client-key"] = self._client_key
        self.send(json.dumps(hello))

    def received_message(self, message) -> None:
        """Handle incoming WebSocket messages."""
        data = json.loads(str(message))

        if data.get("type") == "registered":
            # Registration successful, send pending command if any
            if self.pending_command:
                self.send(json.dumps(self.pending_command))
        elif data.get("type") == "response":
            payload = data.get("payload", {})
            if payload.get("returnValue") is False:
                self.error = payload.get("errorText", "Unknown error")
            else:
                self.result = payload
            self.command_done = True
        elif data.get("type") == "error":
            self.error = data.get("error", "Unknown error")
            self.command_done = True

    def _wait_for_result(self) -> bool:
        """Wait for command to complete. Returns True on success."""
        start = time.time()
        while not self.command_done and (time.time() - start) < CONNECT_TIMEOUT:
            time.sleep(POLL_INTERVAL)
        return self.command_done and self.error is None

    @contextmanager
    def _connection(self):
        """
        Context manager for TV connection with socket timeout.

        Handles socket timeout setup/restore and cleanup. ws4py has no built-in
        connection timeout, so we use socket.setdefaulttimeout() to prevent
        hanging when TV is idle (see module docstring).
        """
        old_timeout = socket.getdefaulttimeout()
        try:
            socket.setdefaulttimeout(SOCKET_TIMEOUT)
            self.connect()
            yield
        finally:
            socket.setdefaulttimeout(old_timeout)
            try:
                self.close()
            except Exception:
                pass

    def execute(self, command: dict) -> dict | None:
        """
        Execute a command on the TV.

        Args:
            command: The command dict to send (type, id, uri, payload).

        Returns:
            The response payload dict on success, None on failure.
            Check self.error for error details on failure.
        """
        self.pending_command = command
        try:
            with self._connection():
                if self._wait_for_result():
                    return self.result
        except Exception as e:
            self.error = str(e)
        return None


# =============================================================================
# TV Settings Helpers
# =============================================================================
def get_system_setting(client: LGTVClient, category: str, key: str) -> Any:
    """Get a single system setting from the TV. Returns the value or None."""
    result = client.execute({
        "type": "request",
        "id": "get_1",
        "uri": "ssap://settings/getSystemSettings",
        "payload": {"category": category, "keys": [key]}
    })
    if result:
        return result.get("settings", {}).get(key)
    return None


def set_system_setting(client: LGTVClient, category: str, **settings) -> bool:
    """Set system settings on the TV. Returns True on success."""
    result = client.execute({
        "type": "request",
        "id": "set_1",
        "uri": "ssap://settings/setSystemSettings",
        "payload": {"category": category, "settings": settings}
    })
    return result is not None


# =============================================================================
# Retry Logic
# =============================================================================
def with_retry(
    ip: str,
    key: str,
    operation: Callable[[LGTVClient], Any],
    error_msg: str,
    notification_title: str = "LG TV",
    on_retry: Callable[[int], None] | None = None
) -> Any:
    """
    Execute TV operation with retry logic for transient SSL errors.

    IMPORTANT: Must create new LGTVClient for each attempt.
    WebSocket connection is closed after each operation - cannot reuse.

    Args:
        ip: TV IP address.
        key: TV authentication key.
        operation: Callable that takes LGTVClient and returns result.
                   Should return None/False on failure, truthy value on success.
        error_msg: Message to show on final failure.
        notification_title: Title for error notification.
        on_retry: Optional callback called before each retry with attempt number.

    Returns:
        Result from operation, or None/False on failure.
    """
    last_error = None

    # Show "Connecting..." if first attempt takes longer than threshold.
    # Uses a timer thread because connect() is a blocking call.
    # When it fires, we skip per-retry notifications to avoid notification spam.
    slow_notified = threading.Event()

    def _slow_notify():
        slow_notified.set()
        notify(notification_title, "Connecting to TV...", "low", 1500)

    slow_timer = threading.Timer(SLOW_CONNECT_THRESHOLD, _slow_notify)
    slow_timer.start()

    for attempt in range(RETRY_ATTEMPTS):
        client = LGTVClient(ip, key)  # Fresh client required - connection is one-shot
        result = operation(client)

        if result is not None and result is not False:
            slow_timer.cancel()
            return result

        last_error = client.error

        if not is_retryable(last_error):
            break

        if attempt < RETRY_ATTEMPTS - 1:
            if on_retry and not slow_notified.is_set():
                on_retry(attempt + 1)
            time.sleep(RETRY_DELAY * (attempt + 1))  # Increasing delay between retries

    slow_timer.cancel()
    notify(notification_title, last_error or error_msg, "critical")
    return result
