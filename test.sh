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


# Function to configure PKI
configure_pki(){
    echo "Configuring PKI..."

    #Generate CA key
    sudo strongswan pki --gen --outform pem > /etc/ipsec.d/cacerts/caPrivateKey.pem

    #Generate CA Cert
    sudo strongswan pki --self --in /etc/ipsec.d/cacerts/caPrivateKey.pem --dn "CN=My VPN CA" --ca --outform pem > /etc/ipsec.d/cacerts/caCert.pem
    
    # Generate server key
    sudo strongswan pki --gen --outform pem > /etc/ipsec.d/private/serverKey.pem

    # Generate server certificate request
    sudo strongswan pki --pub --in /etc/ipsec.d/private/serverKey.pem --outform pem > /etc/ipsec.d/reqs/serverReq.pem
    #Modify it to have server as subjectAltName or CN
    echo "Modify the request /etc/ipsec.d/reqs/serverReq.pem according your needs."

    #Sign the server certificate request with the CA.
    sudo strongswan pki --sign --in /etc/ipsec.d/reqs/serverReq.pem --outform pem --cakey /etc/ipsec.d/cacerts/caPrivateKey.pem --cacert /etc/ipsec.d/cacerts/caCert.pem > /etc/ipsec.d/certs/serverCert.pem

#Generate the client certificates in the same way:
#1. Key: ipsec pki --gen --outform pem > /etc/ipsec.d/private/clientKey.pem
#2. Request: ipsec pki --pub --in /etc/ipsec.d/private/clientKey.pem --outform pem > /etc/ipsec.d/reqs/clientReq.pem
#3. Certificate: ipsec pki --sign --in /etc/ipsec.d/reqs/clientReq.pem --outform pem --cakey /etc/ipsec.d/cacerts/caPrivateKey.pem --cacert /etc/ipsec.d/cacerts/caCert.pem > /etc/ipsec.d/certs/clientCert.pem

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

    cat <<EOF | sudo tee /etc/strongswan.d/ipsec.conf

config setup
    uniqueids = never
    strict_crl_policy = no
    charondebug="ike 1, knl 1, cfg 0"


conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    authby=secret
    mobike=no

        conn roadwarrior
        auto=add
        compress=no
        type=tunnel
        keyexchange=ikev2
        fragmentation=yes
        forceencaps=yes
        ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
        esp=aes256-sha1,aes128-sha1,3des-sha1!
        dpdaction=clear
        dpddelay=300s
        rekey=no
        left=%any
        leftsubnet=0.0.0.0/0,::/0
        leftcert=/etc/ipsec.d/certs/serverCert.pem
        leftid=@SERVER_PUBLIC_IP #replace with the server's public IP address or domain name.
        right=%any
        rightid=%any
        rightsourceip=10.10.10.0/24
        rightdns=8.8.8.8,8.8.4.4
        rightauth=psk
        eap_identity=%identity

EOF
    #Pre-shared key for testing only, generate it securely. This is not good way for production, use Certificates
    echo "Configuring /etc/ipsec.secrets..."
    sudo sh -c "echo ': PSK \"SuperSecurePassword\"' >> /etc/ipsec.secrets"


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
