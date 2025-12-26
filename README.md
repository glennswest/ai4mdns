# ai4mdns

A lightweight mDNS advertisement service for Ollama. Automatically advertises your Ollama instance on the local network, allowing other devices to discover it without manual configuration.

## Features

- Advertises Ollama services via mDNS (`_ollama._tcp.local`)
- Supports both HTTP and HTTPS (TLS) endpoint advertisement
- Automatic IP address detection
- Runs as a systemd service
- Minimal dependencies

## Requirements

- Linux (tested on Ubuntu/Debian)
- Go 1.21 or later (for building)
- systemd (for service management)

## Installation

### Quick Install

```bash
sudo ./install.sh
```

This will:
1. Build the binary from source
2. Install it to `/usr/local/bin/ai4mdns`
3. Install and enable the systemd service
4. Start the service

### Manual Installation

```bash
# Build
go build -o ai4mdns .

# Install binary
sudo cp ai4mdns /usr/local/bin/
sudo chmod +x /usr/local/bin/ai4mdns

# Install systemd service
sudo cp ai4mdns.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ai4mdns
sudo systemctl start ai4mdns
```

## Updating

To update after making changes:

```bash
sudo ./update.sh
```

This rebuilds the binary and restarts the service while preserving your configuration.

## Usage

### Command Line Options

```
ai4mdns [options]

Options:
  -host string
        Hostname to advertise (default: system hostname)
  -instance string
        Service instance name (default "ollama")
  -port int
        Ollama HTTP port to advertise (default 11434)
  -tls
        Also advertise TLS/HTTPS endpoint
  -tls-port int
        Ollama HTTPS port to advertise (requires -tls) (default 443)
```

### Examples

**Basic usage (HTTP only):**
```bash
ai4mdns
```

**Custom port:**
```bash
ai4mdns -port 8080
```

**With TLS/HTTPS advertisement:**
```bash
ai4mdns -tls -tls-port 11435
```

**Custom hostname and instance name:**
```bash
ai4mdns -host myserver.local -instance my-ollama
```

### Running as a Service

The service is managed via systemd:

```bash
# Check status
sudo systemctl status ai4mdns

# Start/stop/restart
sudo systemctl start ai4mdns
sudo systemctl stop ai4mdns
sudo systemctl restart ai4mdns

# View logs
sudo journalctl -u ai4mdns -f

# Enable/disable auto-start on boot
sudo systemctl enable ai4mdns
sudo systemctl disable ai4mdns
```

### Configuring TLS Advertisement

To enable TLS advertisement in the systemd service:

1. Edit the service file:
   ```bash
   sudo systemctl edit ai4mdns
   ```

2. Add an override for ExecStart:
   ```ini
   [Service]
   ExecStart=
   ExecStart=/usr/local/bin/ai4mdns -tls -tls-port 11435
   ```

3. Reload and restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart ai4mdns
   ```

## Advertised Services

### HTTP Service
- **Instance:** `<instance>._ollama._tcp.local`
- **Port:** 11434 (default)
- **TXT Records:** `proto=http`, `ollama`, `llm`, `ai`

### HTTPS Service (when -tls enabled)
- **Instance:** `<instance>-tls._ollama._tcp.local`
- **Port:** 443 (default, configurable via -tls-port)
- **TXT Records:** `proto=https`, `ollama`, `llm`, `ai`

## Discovering Services

### Using the included query tool

```bash
cd query
go run main.go
```

### Using avahi-browse

```bash
avahi-browse -r _ollama._tcp
```

### Using dns-sd (macOS)

```bash
dns-sd -B _ollama._tcp local
```

## Project Structure

```
ai4mdns/
├── main.go           # Main mDNS advertisement service
├── go.mod            # Go module definition
├── go.sum            # Go dependencies
├── ai4mdns.service   # Systemd service unit file
├── install.sh        # Installation script
├── update.sh         # Update script
├── README.md         # This file
└── query/
    ├── main.go       # mDNS query utility
    ├── go.mod
    └── go.sum
```

## Troubleshooting

### Service won't start

Check the logs:
```bash
sudo journalctl -u ai4mdns -e
```

### No IP addresses found

Ensure you have at least one non-loopback network interface with an IPv4 address:
```bash
ip addr show
```

### Services not discoverable

1. Ensure mDNS traffic is allowed through your firewall (UDP port 5353)
2. Check that avahi-daemon is running: `systemctl status avahi-daemon`
3. Verify the service is advertising: `avahi-browse -r _ollama._tcp`

### Port already in use

The mDNS port (5353) may be in use by another service. Check with:
```bash
sudo ss -ulnp | grep 5353
```

## License

MIT
