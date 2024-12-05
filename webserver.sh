#!/bin/bash

# Variables

echo "Enter your local Dir"
read LOCAL_CERT_DIR
# ex : LOCAL_CERT_DIR="/home/user"
echo "Welcome ${LOCAL_CERT_DIR}!"



echo "Enter your username of the distant machine"
read REMOTE_USER
# ex : REMOTE_USER="rayan"
echo "Welcome ${REMOTE_USER}!"

echo "Enter the ip of distant machine"
read REMOTE_HOST
# ex : REMOTE_HOST="192.168.80.141"
echo "Welcome ${REMOTE_HOST}!"


echo "Enter your local Dir"
read REMOTE_CERT_DIR
# ex : LOCAL_CERT_DIR="/etc/ssl/esgi"
echo "Welcome ${LOCAL_CERT_DIR}!"




# Fichiers à copier
CERT_FILES=(
    "esgi.local.cert.pem"
    "esgi.local.key.pem"
    "ca-chain.cert.pem"
)

# Vérification que les fichiers existent
for file in "${CERT_FILES[@]}"; do
    if [ ! -f "$LOCAL_CERT_DIR/$file" ]; then
        echo "Erreur : Fichier $file introuvable dans $LOCAL_CERT_DIR."
        exit 1
    fi
done

# Copier les fichiers sur le serveur distant
echo "Copie des fichiers vers le serveur distant..."
for file in "${CERT_FILES[@]}"; do
    scp "$LOCAL_CERT_DIR/$file" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_CERT_DIR"
    if [ $? -ne 0 ]; then
        echo "Erreur : Échec de la copie de $file."
        exit 1
    fi
done

echo "Configuration des permissions sur le serveur distant..."
ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
sudo chmod 600 $REMOTE_CERT_DIR/esgi.local.key.pem
sudo chmod 644 $REMOTE_CERT_DIR/esgi.local.cert.pem $REMOTE_CERT_DIR/ca-chain.cert.pem
EOF

if [ $? -ne 0 ]; then
    echo "Erreur : Échec de la configuration des permissions sur le serveur distant."
    exit 1
fi

echo "Opération terminée avec succès."
