#!/bin/bash

# StrongSwan VPN Server Installation and Configuration Script

set -e  # Exit immediately if a command exits with a non-zero status

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}




# Function to install StrongSwan
install_strongswan() {
    echo "Updating system and installing StrongSwan..."
    if command_exists apt; then
        sudo apt update
        sudo apt install -y strongswan strongswan-pki
    elif command_exists dnf; then
        sudo dnf install -y strongswan
    else
        echo "Unsupported package manager. Install StrongSwan manually."
        exit 1
    fi
}



# Function to configure the server
configure_server() {
    echo "Configuring StrongSwan server..."

    cat <<EOF | sudo tee /etc/ipsec.conf
    config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

    conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=@$server_domain_or_IP
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
EOF

    echo "Configuring credentials in /etc/ipsec.secrets..."
    read -p "Enter VPN username: " vpn_username
    read -sp "Enter VPN password: " vpn_password
    echo

    cat <<EOF | sudo tee /etc/ipsec.secrets
: RSA "server-key.pem"
$vpn_username : EAP "$vpn_password"
EOF

    sudo systemctl restart strongswan
}

# Function to configure the firewall
configure_firewall() {
    echo "Configuring firewall..."

    public_iface=$(ip route | grep default | awk '{print $5}')
    sudo iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $public_iface -m policy --pol ipsec --dir out -j ACCEPT
    sudo iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $public_iface -j MASQUERADE
    sudo iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.0/24 -o $public_iface -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
    sudo iptables -t filter -A FORWARD --match policy --pol ipsec --dir in --proto esp -s 10.10.10.0/24 -j ACCEPT
    sudo iptables -t filter -A FORWARD --match policy --pol ipsec --dir out --proto esp -d 10.10.10.0/24 -j ACCEPT

    echo "Enabling IPv4 forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo sysctl -w net.ipv4.ip_no_pmtu_disc=1
    sudo sysctl -w net.ipv4.conf.all.send_redirects=0
    sudo sysctl -w net.ipv4.conf.all.accept_redirects=0
    sudo sysctl -p
}

# Main script execution
install_strongswan
configure_pki
configure_server
configure_firewall

echo "StrongSwan VPN server installation and configuration complete."
