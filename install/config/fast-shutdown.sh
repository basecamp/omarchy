# The two faster-shutdown drop-ins
# (etc/systemd/system.conf.d/10-faster-shutdown.conf,
#  etc/systemd/system/user@.service.d/10-faster-shutdown.conf)
# ship via omarchy-settings. Reload systemd so the new drop-ins take effect.
sudo systemctl daemon-reload
