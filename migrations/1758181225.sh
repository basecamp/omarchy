echo "Update Docker daemon configuration with MTU optimization for Tailscale/WireGuard VPNs and improved ulimits"

# Only update if Docker is installed
if command -v docker >/dev/null 2>&1; then
    echo "Updating Docker daemon.json with MTU and ulimits optimization..."
    
    # Backup existing daemon.json if it exists (only during migration, not fresh install)
    if [[ -f /etc/docker/daemon.json ]]; then
        backup_timestamp=$(date +"%Y%m%d%H%M%S")
        sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.${backup_timestamp}"
        echo "Backed up existing daemon.json to daemon.json.bak.${backup_timestamp}"
    fi
    
    # Run the Docker configuration script to apply the updated settings
    bash $OMARCHY_PATH/install/config/docker.sh
    
    echo "Docker daemon configuration updated. Restart Docker service to apply changes:"
    echo "sudo systemctl restart docker"
else
    echo "Docker not installed, skipping Docker configuration update"
fi
