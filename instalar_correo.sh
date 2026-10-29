#!/bin/bash
# Script de automatización para Postfix y Dovecot

# 1. Solicitar variables de entorno
echo "=== Configuración de Variables ==="
read -r -p "Dominio principal (ej. dominio.com): " DOMINIO_PRINCIPAL
read -r -p "Hostname corto (ej. mail): " HOSTNAME_CORREO
read -r -p "FQDN (ej. mail.dominio.com): " FQDN_CORREO
read -r -p "IP del Servidor (ej. 192.168.100.2): " IP_SERVIDOR
read -r -p "IP del Gateway (ej. 192.168.100.254): " IP_GATEWAY
read -r -p "IP del DNS (ej. 192.168.100.1): " IP_DNS
read -r -p "Red Local (ej. 192.168.100.0/24): " RED_LOCAL
read -r -p "Usuario de Correo a crear (ej. juanperez): " USUARIO_CORREO
read -r -p "Ruta absoluta del certificado del servidor: " RUTA_CERT
read -r -p "Ruta absoluta de la llave privada del servidor: " RUTA_KEY
read -r -p "Ruta absoluta del certificado CA (root): " RUTA_CA

# 2. Preparación del Sistema y Red
echo "=== Preparando Sistema y Red ==="
hostnamectl set-hostname "$HOSTNAME_CORREO" 

cat <<EOF > /etc/hosts
127.0.0.1       localhost
127.0.1.1       $FQDN_CORREO    $HOSTNAME_CORREO
EOF

# Actualizar e instalar paquetes base
apt update && apt upgrade -y 

# 3. Gestión de Certificados SSL/TLS
echo "=== Copiando Certificados Locales ==="
cp "$RUTA_CERT" "/etc/ssl/certs/${HOSTNAME_CORREO}.crt"
cp "$RUTA_KEY" "/etc/ssl/private/${HOSTNAME_CORREO}.key"
cp "$RUTA_CA" /etc/ssl/certs/ca-root.crt

chmod 600 "/etc/ssl/private/${HOSTNAME_CORREO}.key" 
chown root:root "/etc/ssl/private/${HOSTNAME_CORREO}.key" 

# 4. Instalación y Configuración de Postfix
echo "=== Instalando y configurando Postfix ==="
apt install -y postfix mailutils #

cp /etc/postfix/main.cf /etc/postfix/main.cf.bak 
cat <<EOF > /etc/postfix/main.cf
# Nivel de compatibilidad y dominios
compatibility_level = 3.9
mydomain = $DOMINIO_PRINCIPAL
myorigin = \$mydomain
myhostname = $FQDN_CORREO
mydestination = \$myhostname, $DOMINIO_PRINCIPAL, localhost.\$mydomain, localhost

# Red e Interfaces
inet_protocols = ipv4
inet_interfaces = all
mynetworks_style = host
mynetworks = 127.0.0.0/8 $RED_LOCAL

# Buzones de correo (Maildir)
mailbox_size_limit = 0
home_mailbox = Maildir/
mailbox_command = 
recipient_delimiter = +
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

# Configuración TLS
smtpd_tls_key_file = /etc/ssl/private/${HOSTNAME_CORREO}.key
smtpd_tls_cert_file = /etc/ssl/certs/${HOSTNAME_CORREO}.crt
smtp_tls_CAfile = /etc/ssl/certs/ca-root.crt
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_tls_auth_only = yes
smtpd_tls_loglevel = 1

# Autenticación SASL integrada con Dovecot
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname

# Restricciones de envío
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
EOF

cp /etc/postfix/master.cf /etc/postfix/master.cf.bak #
cat <<EOF > /etc/postfix/master.cf

smtp      inet  n       -       y       -       -       smtpd



submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
  -o syslog_name=\${multi_instance_name?{\$multi_instance_name}:{postfix}}/\$service_name
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd

EOF

# 5. Instalación y Configuración de Dovecot
echo "=== Instalando y configurando Dovecot ==="
apt install -y dovecot-imapd dovecot-pop3d 

cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf.bak #
cat <<EOF > /etc/dovecot/conf.d/10-ssl.conf
# Requerir SSL y definir rutas de certificados
ssl = required
ssl_server_cert_file = /etc/ssl/certs/${HOSTNAME_CORREO}.crt
ssl_server_key_file = /etc/ssl/private/${HOSTNAME_CORREO}.key
ssl_server_ca_file = /etc/ssl/certs/ca-root.crt

# Protocolo mínimo aceptado
ssl_min_protocol = TLSv1.2
EOF

cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.bak 
cat <<EOF > /etc/dovecot/conf.d/10-auth.conf
!include auth-system.conf.ext
EOF

cp /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.bak 
cat <<EOF > /etc/dovecot/conf.d/10-master.conf
service imap-login {
  inet_listener imap {

  }
  inet_listener imaps {

  }
}

service pop3-login {
  inet_listener pop3 {

  }
  inet_listener pop3s {


  }
}

service submission-login {
  inet_listener submission {

  }
  inet_listener submissions {

  }
}

service lmtp {
  unix_listener lmtp {

  }

}

service imap {
}

service pop3 {

}

service submission {

}

service auth {
  unix_listener auth-userdb {
    mode = 0660
    user = postfix
    group = postfix
  }

  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix  
}

}

service auth-worker {

}

service dict {
  unix_listener dict {

  }
}


EOF


# 6. Creación de Usuarios y Estructura Maildir
echo "=== Creando Usuario y Maildir ==="
useradd -m -s /sbin/nologin -c "Usuario de Correo" "$USUARIO_CORREO" 
echo "Asignar contraseña para el usuario $USUARIO_CORREO:"
passwd "$USUARIO_CORREO"

mkdir -p /home/"$USUARIO_CORREO"/Maildir/{new,cur,tmp} 
chown -R "$USUARIO_CORREO":"$USUARIO_CORREO" /home/"$USUARIO_CORREO"/Maildir/ 
chmod -R 700 /home/"$USUARIO_CORREO"/Maildir/


cat <<EOF > /etc/network/interfaces
# The primary network interface
allow-hotplug enp0s3
iface enp0s3 inet static
    address $IP_SERVIDOR
    netmask 255.255.255.0
    gateway $IP_GATEWAY
EOF

cat <<EOF > /etc/resolv.conf
search $DOMINIO_PRINCIPAL
nameserver $IP_DNS
EOF

echo "=== Reiniciando y habilitando servicios ==="
systemctl restart postfix dovecot 
systemctl enable postfix dovecot

echo "=== Instalación finalizada ==="
echo "Puedes comprobar el estado con: systemctl status postfix dovecot"