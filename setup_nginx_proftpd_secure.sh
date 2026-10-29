#!/bin/bash

# ==========================================
# Fase 0: Verificación de privilegios de root
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "Error: Este script debe ser ejecutado como root."
  exit 1
fi

# ==========================================
# Fase 1: Recolección de variables del usuario
# ==========================================
echo "--- Configuración Base ---"
read -r -p "Nombre del servidor (HOSTNAME, ej. gamma): " HOSTNAME
read -r -p "Dominio principal (DOMINIO_WEB, ej. xeon.cr): " DOMINIO_WEB
read -r -p "Nombre de dominio completamente calificado (FQDN, ej. gamma.xeon.cr): " FQDN
read -r -p "Dirección IP estática del servidor (ej. 192.168.106.3): " IP_SERVIDOR
read -r -p "Máscara de red (ej. 255.255.255.0): " MASCARA_RED
read -r -p "Puerta de enlace (Gateway, ej. 192.168.106.254): " PUERTA_ENLACE
read -e -p "Dirección IP del DNS (ej. 192.168.106.1): " IP_DNS
read -r -p "Interfaz de red principal (ej. enp0s3): " INTERFAZ_RED
read -r -p "Ruta raíz web (ej. /var/www/xeon.cr): " RUTA_RAIZ_WEB
read -r -p "Usuario FTP para administrar la web (ej. webadmin): " USUARIO_FTP
CREADOR="Daril Arias"

echo "--- Rutas de Certificados y Llaves ---"
read -r -p "Ruta absoluta de la llave SSL (.key): " RUTA_LLAVE
read -r -p "Ruta absoluta del certificado CA (.crt): " RUTA_CERT_CA
read -r -p "Ruta absoluta del certificado SSL (.crt): " RUTA_CERT_SSL

# Asignar nombres fijos destino para facilitar la configuración en los archivos
DEST_LLAVE="${DOMINIO_WEB}.key"
DEST_CERT_CA="ca_${DOMINIO_WEB}.crt"
DEST_CERT_SSL="${DOMINIO_WEB}.crt"

# ==========================================
# Fase 2: Configuración Base del Sistema
# ==========================================
echo "Configurando hostname..."
hostnamectl set-hostname "$HOSTNAME"

echo "Configurando /etc/hosts..."
cat <<EOF > /etc/hosts
127.0.0.1       localhost
127.0.1.1       $FQDN   $HOSTNAME
EOF

echo "Actualizando repositorios e instalando paquetes base..."
apt update && apt upgrade -y

# ==========================================
# Fase 3: Despliegue y Configuración de Nginx
# ==========================================
echo "Instalando Nginx..."
apt install nginx -y
mkdir -p "$RUTA_RAIZ_WEB/html"

echo "Creando archivo index.html de prueba..."
cat <<EOF > "$RUTA_RAIZ_WEB/html/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bienvenido a $DOMINIO_WEB</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background-color: #f4f4f9; }
        h1 { color: #2c3e50; }
        p { color: #34495e; font-size: 1.2em; }
        .footer { margin-top: 40px; font-size: 0.9em; color: #7f8c8d; border-top: 1px solid #ccc; padding-top: 10px; }
    </style>
</head>
<body>
    <h1>¡El servidor para $DOMINIO_WEB está en línea!</h1>
    <p>La configuración de Nginx con SSL y ProFTPD ha finalizado correctamente.</p>
    <div class="footer">Desplegado y configurado por: <strong>$CREADOR</strong></div>
</body>
</html>
EOF

echo "Transfiriendo y asegurando certificados..."
cp "$RUTA_LLAVE" "/etc/ssl/private/$DEST_LLAVE"
chown root:root "/etc/ssl/private/$DEST_LLAVE"
chmod 600 "/etc/ssl/private/$DEST_LLAVE"

cp "$RUTA_CERT_CA" "/etc/ssl/certs/$DEST_CERT_CA"
chown root:root "/etc/ssl/certs/$DEST_CERT_CA"
chmod 644 "/etc/ssl/certs/$DEST_CERT_CA"

cp "$RUTA_CERT_SSL" "/etc/ssl/certs/$DEST_CERT_SSL"
chown root:root "/etc/ssl/certs/$DEST_CERT_SSL"
chmod 644 "/etc/ssl/certs/$DEST_CERT_SSL"

echo "Creando Virtual Host para Nginx..."
cat <<EOF > "/etc/nginx/sites-available/$DOMINIO_WEB"
# Redirección obligatoria de HTTP a HTTPS
server {
    listen 80;
    server_name $DOMINIO_WEB www.$DOMINIO_WEB;
    return 301 https://\$host\$request_uri;
}

# Bloque principal para conexiones HTTPS
server {
    listen 443 ssl;
    server_name $DOMINIO_WEB www.$DOMINIO_WEB;
    root $RUTA_RAIZ_WEB/html;
    index index.html index.htm;

    ssl_certificate /etc/ssl/certs/$DEST_CERT_SSL;
    ssl_certificate_key /etc/ssl/private/$DEST_LLAVE;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ =404;
    }

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
}
EOF

echo "Habilitando sitio en Nginx..."
ln -sf "/etc/nginx/sites-available/$DOMINIO_WEB" /etc/nginx/sites-enabled/

# ==========================================
# Fase 4: Gestión de Usuarios y Permisos
# ==========================================
echo "Creando usuario FTP..."
useradd -m -d "$RUTA_RAIZ_WEB" -s /usr/sbin/nologin "$USUARIO_FTP"
echo "Por favor, asigne una contraseña para el usuario FTP ($USUARIO_FTP):"
passwd "$USUARIO_FTP"

echo "Ajustando permisos del directorio web..."
chown -R "$USUARIO_FTP":www-data "$RUTA_RAIZ_WEB"
chmod -R 775 "$RUTA_RAIZ_WEB"

# ==========================================
# Fase 5: Despliegue y Configuración de ProFTPD
# ==========================================
echo "Instalando ProFTPD y módulo TLS..."
apt install proftpd-basic proftpd-mod-crypto -y

echo "Configurando proftpd.conf..."
cat <<EOF > /etc/proftpd/proftpd.conf
Include /etc/proftpd/modules.conf
UseIPv6 on

<IfModule mod_ident.c>
    IdentLookups off
</IfModule>

ServerName "$HOSTNAME FTP Server"
ServerType standalone
DefaultServer on

TimeoutNoTransfer 600
TimeoutStalled 600
TimeoutIdle 1200

DeferWelcome off
ShowSymlinks on
DisplayLogin welcome.msg
DisplayChdir .message true
ListOptions "-l"
DenyFilter \*.*/

DefaultRoot ~
RequireValidShell off
Port 21
MaxInstances 30
User proftpd
Group nogroup
Umask 022 022
AllowOverwrite on

TransferLog /var/log/proftpd/xferlog
SystemLog /var/log/proftpd/proftpd.log

<IfModule mod_delay.c>
    DelayEngine on
</IfModule>

Include /etc/proftpd/tls.conf

<Limit LOGIN>
  AllowUser $USUARIO_FTP
  DenyAll
</Limit>

Include /etc/proftpd/conf.d/
EOF

echo "Configurando tls.conf de ProFTPD..."
cat <<EOF > /etc/proftpd/tls.conf
<IfModule mod_tls.c>
    TLSEngine on
    TLSLog /var/log/proftpd/tls.log
    TLSProtocol TLSv1.2 TLSv1.3

    TLSRSACertificateFile /etc/ssl/certs/$DEST_CERT_SSL
    TLSRSACertificateKeyFile /etc/ssl/private/$DEST_LLAVE
    TLSCACertificateFile /etc/ssl/certs/$DEST_CERT_CA

    TLSVerifyClient off
    TLSRequired on
</IfModule>
EOF

echo "Habilitando mod_tls.c en modules.conf..."
sed -i 's/^#\s*LoadModule mod_tls.c/LoadModule mod_tls.c/' /etc/proftpd/modules.conf

# ==========================================
# Fase 6: Verificación y Control de Servicios
# ==========================================
echo "Configurando IP estática..."
cat <<EOF > /etc/network/interfaces
# Interfaz de red principal
allow-hotplug $INTERFAZ_RED
iface $INTERFAZ_RED inet static
    address $IP_SERVIDOR
    netmask $MASCARA_RED
    gateway $PUERTA_ENLACE
EOF

echo "Configurando resolución DNS..."
cat <<EOF > /etc/resolv.conf
nameserver $IP_DNS
search $DOMINIO_WEB
EOF
#============================================
echo "Verificando sintaxis de Nginx..."
nginx -t

echo "Verificando sintaxis de ProFTPD..."
proftpd -t

echo "Reiniciando servicios..."
systemctl restart nginx
systemctl restart proftpd

echo "¡Despliegue finalizado exitosamente!"