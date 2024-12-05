#!/bin/bash

# StrongSwan VPN Server Installation and Configuration Script

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install StrongSwan
install_strongswan() {
    echo "Updating system and installing StrongSwan..."
    if command_exists apt; then
        sudo apt update
        sudo apt install -y strongswan strongswan-pki libcharon-extra-plugins
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

    cat <<EOF | sudo tee /etc/strongswan.d/charon.conf
charon {
    load = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
    #filelog = /var/log/charon.log # if you want file logging
}

include /etc/strongswan.d/*.conf
include /usr/share/strongswan/charon/*.conf

EOF

cat <<EOF | sudo tee /etc/strongswan.d/strongswan.conf
    charon {
            threads = 16
            dns1 = 8.8.8.8
            nbns1 = 10.1.1.1
    }
    pluto {

    }
    libstrongswan {
            crypto_test {
                    on_add = yes
            }
    }
EOF
ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
    cat <<EOF | sudo tee /etc/strongswan.d/ipsec.conf

    conn %default
            ikelifetime=60m
            keylife=20m
            rekeymargin=3m
            keyingtries=1

    conn roadwarrior-base
            left=%any
            leftid=@gateway.example.com
            leftfirewall=yes
            right=%any
            rightsourceip=$HERE/16
            auto=add

    conn rw-ikev1-psk-xauth-splittun
            also=roadwarrior-base
            keyexchange=ikev1
            leftsubnet=0.0.0.0/0,::/0
            leftauth=psk
            rightauth=psk
            rightauth2=xauth
    EOF
EOF
    #Pre-shared key for testing only, generate it securely. This is not good way for production, use Certificates
    echo "Configuring /etc/ipsec.secrets..."
    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
    cat <<EOF | sudo tee /etc/ipsec.secrets"
    # pre-shared key
    gateway.example.com %any : PSK "my super secret pre-shared key goes here"

    user1@example.com : XAUTH "password 1"
    user2@exmaple.com : XAUTH "password 2"

    sudo systemctl restart strongswan
    EOF
EOF
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
