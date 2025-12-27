#!/bin/bash
set -e

# ai4mdns installation script
# Downloads and installs the Ollama mDNS advertisement service from GitHub releases

REPO="glennswest/ai4mdns"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/ai4mdns.service"

echo "=== ai4mdns Installation ==="

# Check for root/sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo or as root"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        BINARY_ARCH="amd64"
        ;;
    aarch64|arm64)
        BINARY_ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH ($BINARY_ARCH)"

# Get latest release tag from GitHub
echo "Fetching latest release..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_RELEASE" ]]; then
    echo "Error: Could not fetch latest release. Using 'v1.0.0' as fallback."
    LATEST_RELEASE="v1.0.0"
fi

echo "Latest release: $LATEST_RELEASE"

# Download binary
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_RELEASE}/ai4mdns-linux-${BINARY_ARCH}"
TMP_FILE="/tmp/ai4mdns-$$"

echo "Downloading from: $DOWNLOAD_URL"
if ! curl -fsSL -o "$TMP_FILE" "$DOWNLOAD_URL"; then
    echo "Error: Failed to download binary"
    exit 1
fi

# Stop existing service if running
if systemctl is-active --quiet ai4mdns 2>/dev/null; then
    echo "Stopping existing ai4mdns service..."
    systemctl stop ai4mdns
fi

# Install binary
echo "Installing binary to $INSTALL_DIR..."
mv "$TMP_FILE" "$INSTALL_DIR/ai4mdns"
chmod +x "$INSTALL_DIR/ai4mdns"

# Create systemd service file
echo "Creating systemd service..."
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Ollama mDNS Advertisement Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ai4mdns -tls -tls-port 11435
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "Enabling ai4mdns service..."
systemctl daemon-reload
systemctl enable ai4mdns

# Start service
echo "Starting ai4mdns service..."
systemctl start ai4mdns

# Install and configure Caddy for TLS termination
echo ""
echo "=== Setting up Caddy TLS Proxy ==="

# Check if Caddy is already installed
if command -v caddy &> /dev/null; then
    echo "Caddy is already installed: $(caddy version)"
else
    echo "Installing Caddy..."

    # Install prerequisites
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null 2>&1

    # Add Caddy GPG key
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null

    # Add Caddy repository
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

    # Install Caddy
    apt-get update -qq && apt-get install -y caddy > /dev/null 2>&1

    if command -v caddy &> /dev/null; then
        echo "Caddy installed successfully: $(caddy version)"
    else
        echo "Warning: Failed to install Caddy. TLS proxy will not be available."
    fi
fi

# Configure Caddy for Ollama TLS proxy
CADDY_CONFIG="/etc/caddy/Caddyfile"
if command -v caddy &> /dev/null; then
    echo "Configuring Caddy TLS proxy on port 11435..."

    # Backup existing config if it exists and isn't ours
    if [[ -f "$CADDY_CONFIG" ]] && ! grep -q "Ollama TLS reverse proxy" "$CADDY_CONFIG" 2>/dev/null; then
        cp "$CADDY_CONFIG" "${CADDY_CONFIG}.backup"
        echo "Backed up existing Caddyfile to ${CADDY_CONFIG}.backup"
    fi

    cat > "$CADDY_CONFIG" << 'CADDYEOF'
{
    auto_https off
}

# Ollama TLS reverse proxy
https://:11435 {
    tls internal {
        on_demand
    }
    reverse_proxy localhost:11434
}

# Keep default site on :80
:80 {
    root * /usr/share/caddy
    file_server
}
CADDYEOF

    # Restart Caddy
    systemctl enable caddy > /dev/null 2>&1
    systemctl restart caddy

    # Verify TLS is working
    sleep 2
    if curl -ks https://localhost:11435/api/version > /dev/null 2>&1; then
        echo "Caddy TLS proxy is working on port 11435"
    else
        echo "Warning: Caddy TLS proxy may not be working correctly"
    fi
fi

# Show status
echo ""
echo "=== Installation Complete ==="
systemctl status ai4mdns --no-pager

echo ""
echo "ai4mdns is now running and will start automatically on boot."
echo ""
echo "Endpoints:"
echo "  HTTP:  http://$(hostname):11434"
echo "  HTTPS: https://$(hostname):11435 (via Caddy TLS proxy)"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status ai4mdns   - Check mDNS service status"
echo "  sudo systemctl status caddy     - Check TLS proxy status"
echo "  sudo systemctl stop ai4mdns     - Stop the mDNS service"
echo "  sudo systemctl start ai4mdns    - Start the mDNS service"
echo "  sudo journalctl -u ai4mdns -f   - View mDNS logs"
echo "  sudo journalctl -u caddy -f     - View Caddy logs"
echo ""
echo "To modify TLS settings, edit $SERVICE_FILE"
echo "and update ExecStart, then run:"
echo "  sudo systemctl daemon-reload && sudo systemctl restart ai4mdns"
