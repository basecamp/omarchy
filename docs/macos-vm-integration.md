# macOS VM Integration with Docker-OSX

This document describes the macOS virtualization integration in Omarchy, which allows users to run macOS virtual machines using Docker-OSX, following the same patterns as the existing Windows VM integration.

## Overview

The macOS VM integration provides:
- **Easy Installation**: One-command setup via `omarchy-macos-vm install`
- **Menu Integration**: Accessible through the main Omarchy menu system
- **Resource Management**: Interactive selection of RAM, CPU, and disk allocation
- **VNC Connection**: Native VNC client integration for macOS GUI access
- **Lifecycle Management**: Complete install/launch/stop/remove cycle

## Architecture

### Core Components

1. **Main Script**: `bin/omarchy-macos-vm` - Complete macOS VM management
2. **Menu Integration**: Integrated into `bin/omarchy-menu` with dedicated macOS options
3. **Docker Infrastructure**: Leverages existing Docker configuration
4. **Desktop Integration**: Desktop file and icon for seamless launching
5. **VNC Client**: TigerVNC for macOS GUI access

### Key Files

- `bin/omarchy-macos-vm` - Main management script
- `applications/icons/macos.png` - macOS icon for desktop integration
- `install/omarchy-base.packages` - Package dependencies (tigervnc)
- `bin/omarchy-menu` - Menu system integration

## Features

### Installation Process

1. **Prerequisites Check**:
   - KVM virtualization support
   - Available disk space validation
   - Docker daemon status

2. **Resource Selection**:
   - Interactive RAM allocation (4GB-32GB)
   - CPU core selection (2-16 cores)
   - Disk size selection (32GB-512GB)
   - macOS version selection (Catalina, Big Sur, Monterey, Ventura)

3. **Docker Compose Configuration**:
   ```yaml
   services:
     macos:
       image: sickcodes/docker-osx:latest
       container_name: omarchy-macos
       environment:
         RAM_SIZE: "8"
         CPU_CORES: "4"
         DISK_SIZE: "64"
         GENERATE_UNIQUE: "true"
         OSX_VERSION: "Ventura"
       devices:
         - /dev/kvm
         - /dev/net/tun
       cap_add:
         - NET_ADMIN
       ports:
         - 5900:5900  # VNC
         - 6000:6000  # VNC alternative
       volumes:
         - $HOME/.macos:/storage
         - $HOME/macOS:/shared
   ```

### Connection Method

- **VNC Protocol**: Uses TigerVNC client for macOS GUI access
- **Port 5900**: Standard VNC port for connection
- **Auto-scaling**: Automatic resolution detection and scaling
- **Keep-alive Option**: Option to keep VM running after VNC disconnect

### Menu Integration

The macOS VM is integrated into the Omarchy menu system:

1. **Install Menu**: `Install > macOS` - Sets up macOS VM
2. **Remove Menu**: `Remove > macOS` - Removes macOS VM and data

### Desktop Integration

- **Desktop File**: `~/.local/share/applications/macos-vm.desktop`
- **Icon**: macOS icon for visual identification
- **UWSM Integration**: Launches via `uwsm app -- omarchy-macos-vm launch`

## Usage

### Installation

```bash
# Via menu system
omarchy-menu  # Navigate to Install > macOS

# Direct command
omarchy-macos-vm install
```

### Launching

```bash
# Via menu system (Super + Space, then search "macOS")
# Or via desktop file

# Direct command
omarchy-macos-vm launch          # Auto-stop on VNC close
omarchy-macos-vm launch -k       # Keep running after VNC close
```

### Management

```bash
omarchy-macos-vm status          # Check VM status
omarchy-macos-vm stop            # Stop running VM
omarchy-macos-vm remove          # Remove VM and data
```

## Technical Details

### Docker-OSX Integration

The implementation uses the `sickcodes/docker-osx:latest` image, which provides:
- **macOS Virtualization**: Full macOS VM support
- **KVM Acceleration**: Hardware virtualization support
- **VNC Server**: Built-in VNC server for GUI access
- **Resource Management**: Configurable RAM, CPU, and disk allocation

### Network Configuration

- **VNC Port**: 5900 (standard VNC port)
- **Alternative Port**: 6000 (backup VNC port)
- **Web Interface**: Available at http://127.0.0.1:5900

### Storage Management

- **VM Storage**: `~/.macos/` - macOS VM disk images
- **Shared Folder**: `~/macOS/` - Shared files between host and VM
- **Docker Volumes**: Persistent storage for VM data

### Security Considerations

- **KVM Access**: Requires `/dev/kvm` device access
- **Network Privileges**: `NET_ADMIN` capability for networking
- **TUN Device**: `/dev/net/tun` for network virtualization

## Comparison with Windows Integration

| Feature | Windows VM | macOS VM |
|---------|------------|----------|
| **Image** | `dockurr/windows` | `sickcodes/docker-osx` |
| **Connection** | RDP (FreeRDP) | VNC (TigerVNC) |
| **Ports** | 3389, 8006 | 5900, 6000 |
| **Protocol** | Remote Desktop | VNC |
| **Scaling** | Auto-detect from Hyprland | Manual VNC scaling |
| **Keep-alive** | Yes | Yes |

## Troubleshooting

### Common Issues

1. **KVM Not Available**:
   ```bash
   sudo modprobe kvm-intel  # Intel CPUs
   sudo modprobe kvm-amd    # AMD CPUs
   ```

2. **Docker Permission Issues**:
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

3. **Port Conflicts**:
   ```bash
   # Check if ports are in use
   netstat -tlnp | grep :5900
   ```

4. **VNC Connection Issues**:
   ```bash
   # Test VNC connection
   vncviewer 127.0.0.1:5900
   ```

### Logs and Debugging

```bash
# View container logs
docker logs omarchy-macos

# Check container status
docker ps -a | grep omarchy-macos

# View Docker Compose logs
docker-compose -f ~/.config/macos/docker-compose.yml logs
```

## Future Enhancements

1. **Multiple macOS Versions**: Support for running multiple macOS VMs
2. **GPU Passthrough**: Hardware acceleration for better performance
3. **Snapshot Management**: VM snapshot and restore functionality
4. **Network Configuration**: Advanced networking options
5. **Resource Monitoring**: Real-time resource usage monitoring

## Dependencies

- **Docker**: Container runtime
- **Docker Compose**: Multi-container orchestration
- **TigerVNC**: VNC client for macOS GUI access
- **KVM**: Hardware virtualization support
- **Gum**: Interactive CLI prompts

## References

- [Docker-OSX GitHub](https://github.com/sickcodes/Docker-OSX)
- [TigerVNC Documentation](https://tigervnc.org/)
- [KVM Virtualization](https://www.linux-kvm.org/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)


