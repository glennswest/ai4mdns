#!/bin/bash
set -e

# ai4mdns update script
# Rebuilds and updates the ai4mdns binary without modifying service configuration

INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== ai4mdns Update ==="

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

# Check if service is running
SERVICE_WAS_RUNNING=false
if systemctl is-active --quiet ai4mdns 2>/dev/null; then
    SERVICE_WAS_RUNNING=true
    echo "Stopping ai4mdns service..."
    systemctl stop ai4mdns
fi

# Update binary
echo "Updating binary in $INSTALL_DIR..."
cp ai4mdns "$INSTALL_DIR/ai4mdns"
chmod +x "$INSTALL_DIR/ai4mdns"

# Restart service if it was running
if [[ "$SERVICE_WAS_RUNNING" == "true" ]]; then
    echo "Restarting ai4mdns service..."
    systemctl start ai4mdns
    echo ""
    echo "=== Update Complete ==="
    systemctl status ai4mdns --no-pager
else
    echo ""
    echo "=== Update Complete ==="
    echo "Binary updated. Service was not running, so it was not started."
    echo "Run 'sudo systemctl start ai4mdns' to start the service."
fi
