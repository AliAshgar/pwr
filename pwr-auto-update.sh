#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

curl -s https://file.winsnip.xyz/file/uploads/Logo-winsip.sh | bash
echo -e "${CYAN}Starting Auto Install PWR Service Winsnip${NC}"
sleep 5

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local border="-----------------------------------------------------"
    
    echo -e "${border}"
    case $level in
        "INFO")
            echo -e "${CYAN}[INFO] ${timestamp} - ${message}${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS] ${timestamp} - ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR] ${timestamp} - ${message}${NC}"
            ;;
        *)
            echo -e "${YELLOW}[UNKNOWN] ${timestamp} - ${message}${NC}"
            ;;
    esac
    echo -e "${border}\n"
}

common() {
    local duration=$1
    local message=$2
    local end=$((SECONDS + duration))
    local spinner="⣷⣯⣟⡿⣿⡿⣟⣯⣷"
    
    echo -n -e "${YELLOW}${message}...${NC} "
    while [ $SECONDS -lt $end ]; do
        printf "\b${spinner:((SECONDS % ${#spinner}))%${#spinner}:1}"
        sleep 0.1
    done
    printf "\r${GREEN}Done!${NC} \n"
}

echo -e "${CYAN}Enter your information below:${NC}"
read -p "Name: " name
read -p "Wallet Address: " address
read -p "Telegram Bot Token: " bot_token
read -p "Telegram Chat ID: " chat_id

balance_limit=99999
check_interval=3600

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d chat_id="${chat_id}" \
        -d text="${message}" \
        -d parse_mode="HTML"
}

monitor_balance() {
    while true; do
        log "INFO" "Checking balance..."
        
        local response=$(curl -s "https://pwrexplorerv2.pwrlabs.io/balanceOf/?userAddress=$address")
        if [ -z "$response" ]; then
            log "ERROR" "Failed to get balance"
            sleep $check_interval
            continue
        fi
        
        local balance=$(echo $response | grep -Po '"balance":\s*\K[0-9]+' || echo "0")
        local balance_formatted=$(($balance / 1000000000))
        
        log "INFO" "Current balance: $balance_formatted PWR"
        
        if [ $balance_formatted -ge $balance_limit ]; then
            log "SUCCESS" "Balance sufficient (≥$balance_limit PWR)"
            send_telegram "✅ <b>PWR Balance Updated</b> ✅
Name: ${name}
Address: ${address}
Current Balance: ${balance_formatted} PWR
Status: Balance Sufficient"
            break
        else
            log "INFO" "Balance still below $balance_limit PWR"
            send_telegram "⚠️ <b>PWR Balance Reminder</b> ⚠️
Name: ${name}
Address: ${address}
Current Balance: ${balance_formatted} PWR
Required Balance: ${balance_limit} PWR
Status: Still Need Faucet Request"
            sleep $check_interval
        fi
    done
}

check_upgrade() {
    log "INFO" "Checking for updates..."
    
    current_version=$(java -jar validator.jar --version 2>/dev/null | grep -oP "PWR version: \K.*" || echo "unknown")
    if [ "$current_version" = "unknown" ]; then
        log "ERROR" "Cannot detect current version"
        return 1
    fi
    
    latest_version=$(curl -s "https://github.com/pwrlabs/PWR-Validator/releases" | grep -oP '(?<=/pwrlabs/PWR-Validator/releases/tag/)[^"]*' | head -n 1)
    if [ -z "$latest_version" ]; then
        log "ERROR" "Failed to get latest version"
        return 1
    fi

    log "INFO" "Current version: $current_version"
    log "INFO" "Latest version : $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log "INFO" "Already running latest version"
        monitor_balance
        return 1
    fi

    log "INFO" "New version available. Starting automatic upgrade..."
    if sudo systemctl stop pwr.service && \
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
       sudo systemctl restart pwr
       sleep 300
       sudo systemctl stop pwr.service
       sudo pkill -f java
       sudo systemctl restart pwr; then
        
        log "SUCCESS" "Upgrade completed successfully"
        send_telegram "✅ <b>PWR Upgrade Success</b> ✅
Name: ${name}
Previous Version: ${current_version}
New Version: ${latest_version}
Status: Upgrade Completed Successfully
Time: $(date '+%Y-%m-%d %H:%M:%S')"
        
        monitor_balance
    else
        log "ERROR" "Upgrade failed"
        send_telegram "❌ <b>PWR Upgrade Failed</b> ❌
Name: ${name}
Current Version: ${current_version}
Attempted Version: ${latest_version}
Status: Upgrade Failed
Time: $(date '+%Y-%m-%d %H:%M:%S')
Action Required: Please check manually!"
        return 1
    fi
    
    return 0
}

while true; do
    clear
    log "INFO" "Starting PWR management script..."
    log "INFO" "Current time: $(date '+%Y-%m-%d %H:%M:%S')"
    check_upgrade
    log "INFO" "Waiting 1 hour before next version check..."
    log "INFO" "Next check at: $(date -d "+1 hour" '+%Y-%m-%d %H:%M:%S')"
    sleep 3600  
done
