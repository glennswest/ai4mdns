package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/hashicorp/mdns"
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

	// Get local IP addresses for the service
	ips, err := getLocalIPs()
	if err != nil {
		log.Fatalf("Failed to get local IPs: %v", err)
	}

	if len(ips) == 0 {
		log.Fatal("No local IP addresses found")
	}

	// Create HTTP mDNS service
	httpService, err := mdns.NewMDNSService(
		*instance,       // Instance name
		"_ollama._tcp",  // Service type
		"",              // Domain (empty = .local)
		hostname+".",    // Host name
		*port,           // Port
		ips,             // IPs
		[]string{"proto=http", "ollama", "llm", "ai"}, // TXT records
	)
	if err != nil {
		log.Fatalf("Failed to create HTTP mDNS service: %v", err)
	}

	// Create HTTP mDNS server
	httpServer, err := mdns.NewServer(&mdns.Config{Zone: httpService})
	if err != nil {
		log.Fatalf("Failed to create HTTP mDNS server: %v", err)
	}
	defer httpServer.Shutdown()

	log.Printf("Advertising Ollama HTTP service via mDNS:")
	log.Printf("  Instance: %s", *instance)
	log.Printf("  Service:  _ollama._tcp.local")
	log.Printf("  Host:     %s", hostname)
	log.Printf("  Port:     %d", *port)
	log.Printf("  Proto:    http")
	log.Printf("  IPs:      %v", ips)

	// Optionally create HTTPS mDNS service
	if *tls {
		tlsService, err := mdns.NewMDNSService(
			*instance+"-tls", // Instance name (distinct from HTTP)
			"_ollama._tcp",   // Same service type
			"",               // Domain (empty = .local)
			hostname+".",     // Host name
			*tlsPort,         // TLS Port
			ips,              // IPs
			[]string{"proto=https", "ollama", "llm", "ai"}, // TXT records
		)
		if err != nil {
			log.Fatalf("Failed to create HTTPS mDNS service: %v", err)
		}

		tlsServer, err := mdns.NewServer(&mdns.Config{Zone: tlsService})
		if err != nil {
			log.Fatalf("Failed to create HTTPS mDNS server: %v", err)
		}
		defer tlsServer.Shutdown()

		log.Printf("Advertising Ollama HTTPS service via mDNS:")
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

	fmt.Println("\nShutting down mDNS server...")
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
