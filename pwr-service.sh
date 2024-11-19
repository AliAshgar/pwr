#!/bin/bash

log() {
  local type="$1"
  local message="$2"
  local color

  case "$type" in
    info) color="\033[0;34m" ;;
    success) color="\033[0;32m" ;;
    error) color="\033[0;31m" ;;
    *) color="\033[0m" ;;
  esac

  echo -e "${color}${message}\033[0m"
}
curl -s https://file.winsnip.xyz/file/uploads/Logo-winsip.sh | bash
sleep 5

echo -e "\n\n############ PWR Service Winsnip ############\n"
sleep 2

exists() {
  command -v "$1" >/dev/null 2>&1
}

validate_ip() {
    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

while true; do
    log "info" "=== PWR Node Management ==="
    log "info" "1. Install New Node"
    log "info" "2. Upgrade Existing Node"
    log "info" "3. Check System Status"
    log "info" "0. Exit"
    log "info" "=========================="
    
    read -p "Choose an option: " choice
    case $choice in
        1) 

            log "info" "Updating and upgrading system..."
            if ! sudo apt update && sudo apt upgrade -y; then
                log "error" "Failed to update system"
                exit 1
            fi

            for pkg in curl wget ufw; do
                if ! exists $pkg; then
                    log "error" "$pkg not found. Installing..."
                    if ! sudo apt install $pkg -y; then
                        log "error" "Failed to install $pkg"
                        exit 1
                    fi
                else
                    log "success" "$pkg is already installed."
                fi
            done

            clear
            log "info" "Run and Install Start..."
            sleep 1

            log "info" "Checking for existing installation..."

            if systemctl is-active --quiet pwr.service; then
                log "info" "Stopping existing PWR service..."
                sudo systemctl stop pwr.service
                sudo systemctl disable pwr.service
            fi

            log "info" "Cleaning up old files..."
            sudo rm -rf validator.jar config.json blocks rocksdb
            if [ -f "/etc/systemd/system/pwr.service" ]; then
                sudo rm /etc/systemd/system/pwr.service
            fi

            sudo systemctl daemon-reload

            log "info" "Cleanup completed. Starting fresh installation..."

            log "info" "Please provide the following information:"
            read -p "Enter your desired password: " PASSWORD
            echo
            read -p "Enter your private key: " PRIVATE_KEY
            echo

            while true; do
                read -p "Enter your server IP (e.g., 185.192.97.28): " SERVER_IP
                if validate_ip "$SERVER_IP"; then
                    break
                else
                    log "error" "Invalid IP format. Please try again."
                fi
            done

            log "info" "Configuring firewall..."

            check_port() {
                local port=$1
                local protocol=$2
                if sudo ufw status | grep -q "$port/$protocol"; then
                    log "success" "Port $port/$protocol already open"
                    return 0
                else
                    log "info" "Opening port $port/$protocol..."
                    sudo ufw allow $port/$protocol
                    return 1
                fi
            }

            check_port 22 tcp
            check_port 8231 tcp
            check_port 8085 tcp
            check_port 7621 udp

            if ! sudo ufw status | grep -q "Status: active"; then
                log "info" "Enabling UFW firewall..."
                sudo ufw --force enable
            else
                log "success" "UFW firewall already enabled"
            fi

            log "info" "Installing Java..."
            if ! sudo apt install -y openjdk-17-jre-headless; then
                log "error" "Failed to install Java"
                exit 1
            fi

            log "info" "Downloading PWR Validator..."
            latest_version=$(curl -s "https://github.com/pwrlabs/PWR-Validator/releases" | grep -oP '(?<=/pwrlabs/PWR-Validator/releases/tag/)[^"]*' | head -n 1)
            if [ -z "$latest_version" ]; then
                log "error" "Failed to get latest version"
                exit 1
            fi

            if ! wget "https://github.com/pwrlabs/PWR-Validator/releases/download/$latest_version/validator.jar"; then
                log "error" "Failed to download validator.jar"
                exit 1
            fi

            if ! wget "https://github.com/pwrlabs/PWR-Validator/raw/refs/heads/main/config.json"; then
                log "error" "Failed to download config.json"
                exit 1
            fi

            echo "$PASSWORD" | sudo tee password > /dev/null
            sudo chmod 600 password

            log "info" "Importing private key..."
            java -jar validator.jar --import-key $PRIVATE_KEY password $SERVER_IP --compression-level 0

            sudo tee /etc/systemd/system/pwr.service > /dev/null <<EOF
[Unit]
Description=PWR node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME
ExecStart=java -jar validator.jar password $SERVER_IP --loop-udp-test &
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

            log "info" "Starting PWR service..."
            if ! sudo systemctl daemon-reload; then
                log "error" "Failed to reload systemd"
                exit 1
            fi

            if ! sudo systemctl enable pwr.service; then
                log "error" "Failed to enable PWR service"
                exit 1
            fi

            if ! sudo systemctl start pwr.service; then
                log "error" "Failed to start PWR service"
                exit 1
            fi

            log "success" "PWR node setup complete and service started."
            log "info" "Current service status:"
            sudo systemctl status pwr

            log "info" "Showing live logs (press Ctrl+C to exit):"
            sudo journalctl -u pwr -f
            exit 0
            ;;
        2)
            log "info" "Starting upgrade process..."

            latest_version=$(curl -s "https://github.com/pwrlabs/PWR-Validator/releases" | grep -oP '(?<=/pwrlabs/PWR-Validator/releases/tag/)[^"]*' | head -n 1)
            if [ -z "$latest_version" ]; then
                log "error" "Failed to get latest version"
                exit 1
            fi

            current_version=$(java -jar validator.jar --version 2>/dev/null || echo "unknown")
            
            log "info" "Current version: $current_version"
            log "info" "Latest version : $latest_version"

            if [ "$current_version" = "$latest_version" ]; then
                log "info" "You are already running the latest version."
                read -p "Do you still want to proceed with reinstall? (y/n): " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    log "info" "Upgrade cancelled."
                    exit 0
                fi
            fi
            
            log "info" "Upgrading to version $latest_version..."
            sudo systemctl stop pwr.service && \
            sudo rm -rf validator.jar config.json blocks rocksdb && \
            wget "https://github.com/pwrlabs/PWR-Validator/releases/download/$latest_version/validator.jar" && \
            wget https://github.com/pwrlabs/PWR-Validator/raw/refs/heads/main/config.json && \
            sudo ufw allow 8231/tcp && \
            sudo ufw allow 8085/tcp && \
            sudo ufw allow 7621/udp && \
            sudo iptables -A INPUT -p tcp --dport 8085 -j ACCEPT && \
            sudo iptables -A INPUT -p tcp --dport 8231 -j ACCEPT && \
            sudo iptables -A INPUT -p udp --dport 7621 -j ACCEPT && \
            sudo ufw reload && \
            sudo pkill -f java && \
            sudo systemctl restart pwr && \

            log "info" "Upgrade completed. Checking new version..."
            sleep 5
            new_version=$(java -jar validator.jar --version 2>/dev/null || echo "unknown")
            log "success" "Now running version: $new_version"

            log "info" "Showing live logs (press Ctrl+C to exit):"
            sudo journalctl -u pwr -f
            exit 0
            ;;
        3)
            log "info" "=== System Status Check ==="

            log "info" "Checking validator version..."
            current_version=$(java -jar validator.jar --version 2>/dev/null || echo "not installed")
            latest_version=$(curl -s "https://github.com/pwrlabs/PWR-Validator/releases" | grep -oP '(?<=/pwrlabs/PWR-Validator/releases/tag/)[^"]*' | head -n 1)
            
            log "info" "Current version: $current_version"
            log "info" "Latest version : $latest_version"

            log "info" "Checking PWR service status..."
            if systemctl is-active --quiet pwr.service; then
                log "success" "PWR service is running"
            else
                log "error" "PWR service is not running"
            fi

            log "info" "Checking port status..."
            check_port_status() {
                local port=$1
                local protocol=$2
                if sudo ufw status | grep -q "$port/$protocol"; then
                    log "success" "Port $port/$protocol is open"
                else
                    log "error" "Port $port/$protocol is not open"
                fi
            }
            
            check_port_status 22 tcp
            check_port_status 8231 tcp
            check_port_status 8085 tcp
            check_port_status 7621 udp

            log "info" "Checking Java version..."
            if java -version 2>&1 | grep -q "openjdk version"; then
                java -version 2>&1 | head -n 1
                log "success" "Java is installed"
            else
                log "error" "Java is not installed properly"
            fi

            log "info" "Checking firewall status..."
            if sudo ufw status | grep -q "Status: active"; then
                log "success" "Firewall is active"
            else
                log "error" "Firewall is not active"
            fi
            
            read -p "Press Enter to continue..."
            clear
            ;;
        0)
            log "info" "Exiting..."
            exit 0
            ;;
        *)
            log "error" "Invalid option. Please try again."
            sleep 2
            clear
            ;;
    esac
done
