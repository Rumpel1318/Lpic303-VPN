#!/bin/bash

# Vérifier que le script est exécuté avec sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté avec les droits root (sudo)."
    exit 1
fi

# Install Openssl
install_openssl() {
    echo "Updating system and installing Openssl..."
    if command_exists apt; then
        sudo apt update
        sudo apt install -y openssl
    elif command_exists dnf; then
        sudo dnf install -y openssl
    else
        echo "Unsupported package manager. Install Openssl manually."
        exit 1
    fi
}

# Variables globales
CA_DIR="/root/ca"
INTERMEDIATE_DIR="/root/ca/intermediate"
DEFAULT_DAYS=3650

# Créer la structure de base
setup_directories() {
    echo "Création des répertoires nécessaires pour la PKI..."
    sudo mkdir -p "$CA_DIR"/{certs,crl,newcerts,private,csr}
    sudo chmod 700 "$CA_DIR/private"
    sudo touch "$CA_DIR/index.txt"
    echo 1000 | sudo tee "$CA_DIR/serial"

    sudo mkdir -p "$INTERMEDIATE_DIR"/{certs,crl,csr,newcerts,private}
    sudo chmod 700 "$INTERMEDIATE_DIR/private"
    sudo touch "$INTERMEDIATE_DIR/index.txt"
    echo 1000 | sudo tee "$INTERMEDIATE_DIR/serial"
    echo 1000 | sudo tee "$INTERMEDIATE_DIR/crlnumber"
}

# Configuration openssl.cnf pour la CA racine
create_openssl_cnf_root() {
    cat <<EOF | sudo tee "$CA_DIR/openssl.cnf" > /dev/null
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CA_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
default_md        = sha256
default_days      = 7300
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
default_md          = sha256
string_mask         = utf8only
distinguished_name  = req_distinguished_name
prompt              = no

[ req_distinguished_name ]
countryName            = FR
stateOrProvinceName    = Grand-Est
organizationName       = ESGI
commonName             = ESGI Root CA

[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign
EOF
}

# Configuration openssl.cnf pour l'autorité intermédiaire
create_openssl_cnf_intermediate() {
    cat <<EOF | sudo tee "$INTERMEDIATE_DIR/openssl.cnf" > /dev/null
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $INTERMEDIATE_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
crlnumber         = \$dir/crlnumber
private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem
default_md        = sha256
default_days      = 3650
policy            = policy_strict
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext

[ crl_ext ]
authorityKeyIdentifier = keyid:always

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
default_md          = sha256
string_mask         = utf8only
distinguished_name  = req_distinguished_name
prompt              = no

[ req_distinguished_name ]
countryName            = FR
stateOrProvinceName    = Grand-Est
organizationName       = ESGI
commonName             = ESGI Intermediate CA

[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints        = CA:FALSE
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth
subjectAltName          = @alt_names

[ alt_names ]
DNS.1 = example.local
EOF
}

# Création de la CA racine et intermédiaire
create_ca() {
    echo "Génération de la clé privée et du certificat pour la CA racine..."
    sudo openssl genrsa -out "$CA_DIR/private/ca.key.pem" 4096
    sudo chmod 400 "$CA_DIR/private/ca.key.pem"

    sudo openssl req -config "$CA_DIR/openssl.cnf" -key "$CA_DIR/private/ca.key.pem" \
        -new -x509 -days 7300 -sha256 -extensions v3_ca \
        -out "$CA_DIR/certs/ca.cert.pem"
    sudo chmod 444 "$CA_DIR/certs/ca.cert.pem"

    echo "Génération de la clé privée et CSR pour l'autorité intermédiaire..."
    sudo openssl genrsa -out "$INTERMEDIATE_DIR/private/intermediate.key.pem" 4096
    sudo chmod 400 "$INTERMEDIATE_DIR/private/intermediate.key.pem"

    sudo openssl req -config "$INTERMEDIATE_DIR/openssl.cnf" -key "$INTERMEDIATE_DIR/private/intermediate.key.pem" \
        -new -sha256 -out "$INTERMEDIATE_DIR/csr/intermediate.csr.pem"

    echo "Signature du certificat de l'autorité intermédiaire par la CA racine..."
    sudo openssl ca -config "$CA_DIR/openssl.cnf" -extensions v3_ca -days 3650 -notext -md sha256 \
        -in "$INTERMEDIATE_DIR/csr/intermediate.csr.pem" \
        -out "$INTERMEDIATE_DIR/certs/intermediate.cert.pem"
    sudo chmod 444 "$INTERMEDIATE_DIR/certs/intermediate.cert.pem"

    echo "Création de la chaîne de certificats..."
    sudo cat "$INTERMEDIATE_DIR/certs/intermediate.cert.pem" "$CA_DIR/certs/ca.cert.pem" > "$INTERMEDIATE_DIR/certs/ca-chain.cert.pem"
    sudo chmod 444 "$INTERMEDIATE_DIR/certs/ca-chain.cert.pem"
}

# Générer et signer des CSR
manage_csr() {
    echo "1) Générer un CSR"
    echo "2) Signer un CSR"
    read -rp "Choisissez une option : " csr_choice
    case $csr_choice in
        1)
            read -rp "Entrez le nom du certificat (ex: vpnserver1) : " cert_name
            openssl genrsa -out "$INTERMEDIATE_DIR/private/$cert_name.key.pem" 4096
            chmod 400 "$INTERMEDIATE_DIR/private/$cert_name.key.pem"
            openssl req -config "$INTERMEDIATE_DIR/openssl.cnf" \
                -key "$INTERMEDIATE_DIR/private/$cert_name.key.pem" \
                -new -out "$INTERMEDIATE_DIR/csr/$cert_name.csr.pem" \
                -subj "/C=FR/ST=Grand-Est/O=ESGI/OU=IT Department/CN=$cert_name"
            echo "CSR généré : $INTERMEDIATE_DIR/csr/$cert_name.csr.pem"
            ;;
        2)
            read -rp "Entrez le nom du CSR à signer (ex: vpnserver1) : " csr_name
            openssl ca -config "$INTERMEDIATE_DIR/openssl.cnf" \
                -extensions server_cert -days "$DEFAULT_DAYS" -notext -md sha256 \
                -in "$INTERMEDIATE_DIR/csr/$csr_name.csr.pem" \
                -out "$INTERMEDIATE_DIR/certs/$csr_name.cert.pem"
            chmod 444 "$INTERMEDIATE_DIR/certs/$csr_name.cert.pem"
            echo "Certificat signé : $INTERMEDIATE_DIR/certs/$csr_name.cert.pem"
            ;;
        *)
            echo "Option invalide."
            ;;
    esac
}

# Révoquer un certificat
revoke_cert() {
    read -rp "Entrez le nom du certificat à révoquer (ex: vpnserver1) : " cert_name
    openssl ca -config "$INTERMEDIATE_DIR/openssl.cnf" \
        -revoke "$INTERMEDIATE_DIR/certs/$cert_name.cert.pem"
    openssl ca -config "$INTERMEDIATE_DIR/openssl.cnf" -gencrl \
        -out "$INTERMEDIATE_DIR/crl/intermediate.crl.pem"
    echo "Certificat révoqué et CRL mise à jour : $INTERMEDIATE_DIR/crl/intermediate.crl.pem"
}

# Menu principal
while true; do
    echo "1) Créer la CA (racine et intermédiaire)"
    echo "2) Gérer les CSR (générer et signer)"
    echo "3) Révoquer un certificat et générer une CRL"
    echo "4) Quitter"
    read -rp "Choisissez une option : " choice
    case $choice in
        1)
            setup_directories
            create_openssl_cnf_root
            create_openssl_cnf_intermediate
            create_ca
            ;;
        2)
            manage_csr
            ;;
        3)
            revoke_cert
            ;;
        4)
            echo "Au revoir !"
            exit 0
            ;;
        *)
            echo "Option invalide. Réessayez."
            ;;
    esac
done
