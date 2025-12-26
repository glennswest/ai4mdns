package main

import (
	"fmt"
	"time"
	"github.com/hashicorp/mdns"
)

func main() {
	entriesCh := make(chan *mdns.ServiceEntry, 4)
	go func() {
		for entry := range entriesCh {
			fmt.Printf("Found: %s\n", entry.Name)
			fmt.Printf("  Host: %s\n", entry.Host)
			fmt.Printf("  Port: %d\n", entry.Port)
			fmt.Printf("  IPs:  %v %v\n", entry.AddrV4, entry.AddrV6)
			fmt.Printf("  TXT:  %v\n", entry.InfoFields)
		}
	}()
	
	params := mdns.DefaultParams("_ollama._tcp")
	params.Entries = entriesCh
	params.Timeout = 2 * time.Second
	
	err := mdns.Query(params)
	if err != nil {
		fmt.Printf("Query error: %v\n", err)
	}
	close(entriesCh)
}
