#!/bin/bash
set -e

# ai4mdns installation script
# Installs the Ollama mDNS advertisement service

INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/ai4mdns.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== ai4mdns Installation ==="

# Check for root/sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo or as root"
    exit 1
fi

# Check if Go is available
GO_BIN=""
if command -v go &> /dev/null; then
    GO_BIN="go"
elif [[ -x "/usr/local/go/bin/go" ]]; then
    GO_BIN="/usr/local/go/bin/go"
else
    echo "Error: Go is not installed. Please install Go 1.21+ first."
    exit 1
fi

echo "Using Go: $GO_BIN"

# Build the binary
echo "Building ai4mdns..."
cd "$SCRIPT_DIR"
$GO_BIN build -o ai4mdns .

# Stop existing service if running
if systemctl is-active --quiet ai4mdns 2>/dev/null; then
    echo "Stopping existing ai4mdns service..."
    systemctl stop ai4mdns
fi

# Install binary
echo "Installing binary to $INSTALL_DIR..."
cp ai4mdns "$INSTALL_DIR/ai4mdns"
chmod +x "$INSTALL_DIR/ai4mdns"

# Install systemd service
echo "Installing systemd service..."
cp ai4mdns.service "$SERVICE_FILE"

# Reload systemd and enable service
echo "Enabling ai4mdns service..."
systemctl daemon-reload
systemctl enable ai4mdns

# Start service
echo "Starting ai4mdns service..."
systemctl start ai4mdns

# Show status
echo ""
echo "=== Installation Complete ==="
systemctl status ai4mdns --no-pager

echo ""
echo "ai4mdns is now running and will start automatically on boot."
echo ""
echo "Useful commands:"
echo "  sudo systemctl status ai4mdns   - Check service status"
echo "  sudo systemctl stop ai4mdns     - Stop the service"
echo "  sudo systemctl start ai4mdns    - Start the service"
echo "  sudo journalctl -u ai4mdns -f   - View logs"
echo ""
echo "To enable TLS advertisement, edit $SERVICE_FILE"
echo "and add '-tls -tls-port <port>' to ExecStart, then run:"
echo "  sudo systemctl daemon-reload && sudo systemctl restart ai4mdns"
