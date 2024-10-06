#!/bin/bash

exists() {
  command -v "$1" >/dev/null 2>&1
}

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

log "info" "Updating and upgrading system..."
sudo apt update && sudo apt upgrade -y

if ! exists curl; then
  log "error" "curl not found. Installing..."
  sudo apt install curl -y
else
  log "success" "curl is already installed."
fi

if ! exists wget; then
  log "error" "wget not found. Installing..."
  sudo apt install wget -y
else
  log "success" "wget is already installed."
fi

if ! exists ufw; then
  log "error" "ufw not found. Installing..."
  sudo apt install ufw -y
else
  log "success" "ufw is already installed."
fi

clear
log "info" "Run and Install Start..."
sleep 1
curl -s https://raw.githubusercontent.com/Winnode/winnode/main/Logo.sh | bash
sleep 5

log "info" "Please provide the following information:"
read -p "Enter your desired password: " PASSWORD
echo
read -p "Enter your server IP (e.g., 185.192.97.28): " SERVER_IP

log "info" "If you have a private key you want to import then use this command, otherwise skip to the next step."
read -p "Enter your private key (e.g., 0xCedAWIbF....): " PRIVATEKEY

log "info" "Configuring firewall..."
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 8231/tcp
sudo ufw allow 8085/tcp
sudo ufw allow 7621/udp

log "info" "Installing PWR Chain Validator Node..."
sleep 5
sudo apt update
sudo apt install -y openjdk-19-jre-headless

wget https://github.com/pwrlabs/PWR-Validator-Node/raw/main/validator.jar
wget https://github.com/pwrlabs/PWR-Validator-Node/raw/main/config.json

echo "$PASSWORD" | sudo tee password > /dev/null

if [[ "$PRIVATEKEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "PrivateKey valid."
    sudo java -jar validator.jar --import-key "$PRIVATEKEY" password
else
    echo "Invalid private key, mandatory character length is 64 characters, process continues with new wallet.."
fi

sudo tee /etc/systemd/system/pwr.service > /dev/null <<EOF
[Unit]
Description=PWR node
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME
ExecStart=java -jar validator.jar password $SERVER_IP --compression-level 0
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable pwr.service
sudo systemctl start pwr.service

log "success" "PWR node setup complete and service started."

rm -- "$0"

sudo journalctl -u pwr -f
