package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

func main() {
	host := flag.String("host", "", "Hostname to advertise (default: system hostname)")
	port := flag.Int("port", 11434, "Ollama HTTP port to advertise")
	instance := flag.String("instance", "ollama", "Service instance name")
	tls := flag.Bool("tls", false, "Also advertise TLS/HTTPS endpoint")
	tlsPort := flag.Int("tls-port", 443, "Ollama HTTPS port to advertise (requires -tls)")
	flag.Parse()

	hostname := *host
	if hostname == "" {
		var err error
		hostname, err = os.Hostname()
		if err != nil {
			log.Fatalf("Failed to get hostname: %v", err)
		}
	}

	// Get local IP addresses for logging
	ips, err := getLocalIPs()
	if err != nil {
		log.Fatalf("Failed to get local IPs: %v", err)
	}

	if len(ips) == 0 {
		log.Fatal("No local IP addresses found")
	}

	// Check if avahi-publish is available
	if _, err := exec.LookPath("avahi-publish"); err != nil {
		log.Fatal("avahi-publish not found. Install avahi-utils: apt install avahi-utils")
	}

	var processes []*exec.Cmd

	// Start HTTP service advertisement
	httpCmd := exec.Command("avahi-publish", "-s",
		*instance,
		"_ollama._tcp",
		fmt.Sprintf("%d", *port),
		"proto=http", "ollama", "llm", "ai",
	)
	httpCmd.Stdout = os.Stdout
	httpCmd.Stderr = os.Stderr

	if err := httpCmd.Start(); err != nil {
		log.Fatalf("Failed to start HTTP mDNS advertisement: %v", err)
	}
	processes = append(processes, httpCmd)

	log.Printf("Advertising Ollama HTTP service via avahi:")
	log.Printf("  Instance: %s", *instance)
	log.Printf("  Service:  _ollama._tcp.local")
	log.Printf("  Host:     %s", hostname)
	log.Printf("  Port:     %d", *port)
	log.Printf("  Proto:    http")
	log.Printf("  IPs:      %v", ips)

	// Optionally start HTTPS service advertisement
	if *tls {
		tlsCmd := exec.Command("avahi-publish", "-s",
			*instance+"-tls",
			"_ollama._tcp",
			fmt.Sprintf("%d", *tlsPort),
			"proto=https", "ollama", "llm", "ai",
		)
		tlsCmd.Stdout = os.Stdout
		tlsCmd.Stderr = os.Stderr

		if err := tlsCmd.Start(); err != nil {
			log.Fatalf("Failed to start HTTPS mDNS advertisement: %v", err)
		}
		processes = append(processes, tlsCmd)

		log.Printf("Advertising Ollama HTTPS service via avahi:")
		log.Printf("  Instance: %s-tls", *instance)
		log.Printf("  Service:  _ollama._tcp.local")
		log.Printf("  Host:     %s", hostname)
		log.Printf("  Port:     %d", *tlsPort)
		log.Printf("  Proto:    https")
		log.Printf("  IPs:      %v", ips)
	}

	log.Println("Press Ctrl+C to stop...")

	// Wait for interrupt signal
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig

	fmt.Println("\nShutting down mDNS advertisements...")

	// Kill all avahi-publish processes
	for _, cmd := range processes {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}
}

func getLocalIPs() ([]net.IP, error) {
	var ips []net.IP

	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		// Skip loopback and down interfaces
		if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
			continue
		}

		// Skip virtual/container interfaces (docker, bridge, veth, etc.)
		name := iface.Name
		if isVirtualInterface(name) {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok {
				if ipnet.IP.To4() != nil {
					ips = append(ips, ipnet.IP)
				}
			}
		}
	}

	return ips, nil
}

// isVirtualInterface returns true for virtual/container network interfaces
func isVirtualInterface(name string) bool {
	virtualPrefixes := []string{
		"docker", "br-", "veth", "virbr", "lxc", "lxd",
		"flannel", "cni", "calico", "weave", "podman",
	}
	for _, prefix := range virtualPrefixes {
		if len(name) >= len(prefix) && name[:len(prefix)] == prefix {
			return true
		}
	}
	// Also filter docker0 specifically
	return name == "docker0"
}
