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


# check connectivity


# Fichiers à copier
CERT_FILES=
    "esgi.local.cert.pem"
    "esgi.local.key.pem"
    "ca-chain.cert.pem"



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
# Vérifier la présence d'Apache
if ! dpkg -l | grep -qw apache2; then
    echo "Apache2 n'est pas installé. Installation en cours..."
    sudo apt update && sudo apt install -y apache2
    if [ $? -ne 0 ]; then
        echo "Erreur : Échec de l'installation d'Apache2."
        exit 1
    fi
else
    echo "Apache2 est déjà installé."
fi

# Configurer les permissions des certificats
sudo chmod 600 $REMOTE_CERT_DIR/esgi.local.key.pem
sudo chmod 644 $REMOTE_CERT_DIR/esgi.local.cert.pem $REMOTE_CERT_DIR/ca-chain.cert.pem

# Ajouter les certificats dans Apache2
sudo nano /etc/apache2/sites-available/esgi.local.conf  


sudo a2ensite esgi.local.conf  
sudo systemctl reload apache2  


# Ajouter page web
cat <<EOF > output.html
<!DOCTYPE html>
<html>
<body>

<h1>My First Heading</h1>
<p>My first paragraph.</p>

</body>
</html>
EOF


EOF






if [ $? -ne 0 ]; then
    echo "Erreur : Échec de la configuration des permissions sur le serveur distant."
    exit 1
fi

echo "Opération terminée avec succès."
