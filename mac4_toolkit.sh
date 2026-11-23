#!/bin/bash
# =================================================================
# Mac 4 (Backend B + Capture Client) Automation & Test Toolkit
# Team: LANdo
# =================================================================

MY_IP="10.7.7.247"
MY_PORT="3002"
DNS_IP="10.7.5.248"
EDGE_IP="10.7.21.122"
BACKEND_A_IP="10.7.6.183"
TEAM_DOMAIN="app.lando.test"

show_menu() {
    echo ""
    echo "=========================================================="
    echo "  CN Project Phase 1 - Team LANdo                         "
    echo "  Mac 4 (Backend B & Capture Client - Aviral)             "
    echo "  Your IP: $MY_IP (Port $MY_PORT)                          "
    echo "  Mac 1 (DNS): $DNS_IP | Mac 2 (Edge): $EDGE_IP           "
    echo "  Mac 3 (Backend A): $BACKEND_A_IP                        "
    echo "  Domain: $TEAM_DOMAIN                                    "
    echo "=========================================================="
    echo " 1) Start Backend B (Port 3002 - in foreground)"
    echo " 2) Test Local Backend B (curl localhost:3002)"
    echo " 3) Test Mac 3 Backend A (curl $BACKEND_A_IP:3001)"
    echo " 4) Point Mac 4 DNS to Mac 1 ($DNS_IP)"
    echo " 5) Reset Mac 4 DNS to Default (DHCP)"
    echo " 6) Dig Test against Mac 1 DNS ($TEAM_DOMAIN)"
    echo " 7) Test HTTPS Load Balancer (4 requests, expect A B A B)"
    echo " 8) Test Caching (Task F: ETag & 304 Not Modified)"
    echo " 9) Test HTTP/1.1 vs HTTP/2"
    echo "10) Flush local DNS cache"
    echo "11) Run Failure Test 5 (Port 443 vs 8443 on Mac 2)"
    echo " 0) Exit"
    echo ""
    read -p "Select option [0-11]: " opt
}

while true; do
    show_menu
    case $opt in
        1)
            echo "Starting Backend B on 0.0.0.0:3002..."
            export BACKEND=B
            export PORT=3002
            node "$(dirname "$0")/backend/server.js"
            ;;
        2)
            echo "Testing local backend B on port 3002:"
            curl -i http://localhost:3002/api/status
            echo ""
            ;;
        3)
            echo "Testing Mac 3 Backend A on port 3001 ($BACKEND_A_IP:3001):"
            curl -i "http://$BACKEND_A_IP:3001/api/status"
            echo ""
            ;;
        4)
            sudo networksetup -setdnsservers Wi-Fi "$DNS_IP"
            sudo dscacheutil -flushcache
            echo "DNS server set to $DNS_IP."
            scutil --dns | grep -m 1 nameserver
            ;;
        5)
            sudo networksetup -setdnsservers Wi-Fi empty
            sudo dscacheutil -flushcache
            echo "DNS reset to default automatic DHCP."
            ;;
        6)
            echo "dig @$DNS_IP $TEAM_DOMAIN +short:"
            dig @"$DNS_IP" "$TEAM_DOMAIN"
            ;;
        7)
            echo "Running 4 requests to https://$TEAM_DOMAIN/api/status..."
            for i in 1 2 3 4; do
                echo -n "Request $i: "
                curl -si "https://$TEAM_DOMAIN/api/status" | grep -i "x-backend" || echo "Failed to reach edge"
            done
            ;;
        8)
            echo "--- First Request (Full 200 with ETag) ---"
            curl -I "https://$TEAM_DOMAIN/api/cached"
            ETAG=$(curl -sI "https://$TEAM_DOMAIN/api/cached" | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
            echo "Captured ETag: $ETAG"
            echo "--- Conditional Request (Expect 304 Not Modified) ---"
            curl -I -H "If-None-Match: $ETAG" "https://$TEAM_DOMAIN/api/cached"
            ;;
        9)
            echo "Testing HTTP/1.1:"
            curl -sI --http1.1 "https://$TEAM_DOMAIN/api/status" | head -1
            echo "Testing HTTP/2:"
            curl -sI --http2 "https://$TEAM_DOMAIN/api/status" | head -1
            ;;
        10)
            echo "Flushing macOS DNS cache..."
            sudo dscacheutil -flushcache
            sudo killall -HUP mDNSResponder
            echo "DNS cache flushed."
            ;;
        11)
            echo "Testing port 443 on Mac 2 ($EDGE_IP):"
            nc -vz -w 2 "$EDGE_IP" 443
            echo "Testing port 8443 on Mac 2 ($EDGE_IP) - should be refused:"
            nc -vz -w 2 "$EDGE_IP" 8443
            ;;
        0)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
