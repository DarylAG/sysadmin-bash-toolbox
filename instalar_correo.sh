#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Automatización, despliegue y configuración segura de Postfix y 
#            Dovecot para envíos y recepción de correo interno (IMAP/SMTP/SASL).
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

set -euo pipefail

log_info() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

verificar_privilegios() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script requiere privilegios de administrador. Ejecútalo como root o usando sudo."
    exit 1
  fi
}

recoleccion_variables() {
  log_info "Configuración de Variables"
  read -r -p "Dominio principal (ej. dominio.com): " DOMINIO_PRINCIPAL
  read -r -p "Hostname corto (ej. mail): " HOSTNAME_CORREO
  read -r -p "FQDN (ej. mail.dominio.com): " FQDN_CORREO
  read -r -p "IP del Servidor (ej. 192.168.100.2): " IP_SERVIDOR
  read -r -p "IP del Gateway (ej. 192.168.100.254): " IP_GATEWAY
  read -r -p "IP del DNS (ej. 192.168.100.1): " IP_DNS
  read -r -p "Red Local (ej. 192.168.100.0/24): " RED_LOCAL
  read -r -p "Usuario de Correo a crear (ej. juanperez): " USUARIO_CORREO
  read -r -s -p "Contraseña para el usuario $USUARIO_CORREO: " PASSWORD_CORREO
  echo "" # Esto da un salto de línea en la consola después de la contraseña oculta
  read -r -p "Ruta absoluta del certificado del servidor: " RUTA_CERT
  read -r -p "Ruta absoluta de la llave privada del servidor: " RUTA_KEY
  read -r -p "Ruta absoluta del certificado CA (root): " RUTA_CA

  if [[ -z "$DOMINIO_PRINCIPAL" || -z "$FQDN_CORREO" || -z "$USUARIO_CORREO" || -z "$PASSWORD_CORREO" || -z "$RUTA_CERT" ]]; then
    log_error "Todos los campos, incluyendo la contraseña y rutas, son obligatorios."
    exit 1
  fi

  if [[ ! -f "$RUTA_CERT" || ! -f "$RUTA_KEY" || ! -f "$RUTA_CA" ]]; then
    log_error "Uno o más archivos de certificado no existen en las rutas proporcionadas."
    exit 1
  fi
}

preparacion_sistema() {
  log_info "Preparando Sistema y Red"
  # SERVICIO: El hostname debe coincidir con el registro MX/A del DNS para evitar
  # que otros servidores clasifiquen nuestros correos como Spam.
  hostnamectl set-hostname "$HOSTNAME_CORREO" 

  # RELACIÓN CRUZADA: El servidor de correo necesita resolver su propio FQDN localmente
  # antes de consultar al DNS externo, agilizando el enrutamiento interno.
  cat <<EOF > /etc/hosts
  127.0.0.1       localhost
  127.0.1.1       $FQDN_CORREO    $HOSTNAME_CORREO
EOF
}

actualizar_instalar_paquetes() {
  log_info "Actualizando e instalando paquetes base"
  apt update && apt upgrade -y 
  # SERVICIO: Postfix actúa como MTA (Agente de Transferencia) para enviar/enrutar correos.
  # Dovecot actúa como MDA/POP/IMAP (Agente de Entrega) para almacenar y permitir lectura.
  apt install -y postfix mailutils dovecot-imapd dovecot-pop3d 
}

gestion_certificados () {
  log_info "Copiando Certificados Locales"
  cp "$RUTA_CERT" "/etc/ssl/certs/${HOSTNAME_CORREO}.crt"
  cp "$RUTA_KEY" "/etc/ssl/private/${HOSTNAME_CORREO}.key"
  cp "$RUTA_CA" /etc/ssl/certs/ca-root.crt
  
  # SEGURIDAD: La llave privada es el núcleo criptográfico del servidor. 
  # Los permisos 600 garantizan que únicamente el usuario root pueda leerla.
  chmod 600 "/etc/ssl/private/${HOSTNAME_CORREO}.key" 
  chown root:root "/etc/ssl/private/${HOSTNAME_CORREO}.key" 
}

configuracion_postfix_dovecot() {
  log_info "Configurando Postfix y Dovecot"
  cp /etc/postfix/main.cf /etc/postfix/main.cf.bak 
  
  cat <<EOF > /etc/postfix/main.cf
# Nivel de compatibilidad y dominios
compatibility_level = 3.9
mydomain = $DOMINIO_PRINCIPAL
myorigin = \$mydomain
myhostname = $FQDN_CORREO

# SERVICIO: mydestination le dice a Postfix qué dominios son locales. Si recibe un correo
# para estos dominios, lo entrega a Dovecot en lugar de reenviarlo a internet.
mydestination = \$myhostname, $DOMINIO_PRINCIPAL, localhost.\$mydomain, localhost

# Red e Interfaces
inet_protocols = ipv4
inet_interfaces = all
mynetworks_style = host
mynetworks = 127.0.0.0/8 $RED_LOCAL

# Buzones de correo (Maildir)
# SERVICIO: Maildir almacena cada correo como un archivo individual. Es más seguro 
# y resistente a la corrupción que el formato clásico mbox (un solo archivo grande).
mailbox_size_limit = 0
home_mailbox = Maildir/
mailbox_command = 
recipient_delimiter = +
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

# Configuración TLS
# SEGURIDAD: Encriptación del tráfico SMTP entre servidores (puerto 25).
smtpd_tls_key_file = /etc/ssl/private/${HOSTNAME_CORREO}.key
smtpd_tls_cert_file = /etc/ssl/certs/${HOSTNAME_CORREO}.crt
smtp_tls_CAfile = /etc/ssl/certs/ca-root.crt
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_tls_auth_only = yes
smtpd_tls_loglevel = 1

# Autenticación SASL integrada con Dovecot
# RELACIÓN CRUZADA: Postfix delega la validación de contraseñas a Dovecot.
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname

# Restricciones de envío
# SEGURIDAD: Previene que el servidor actúe como un "Open Relay" (usado por spammers).
# Solo permite enviar a quienes autentiquen con contraseña o estén en la red local.
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
EOF

  cp /etc/postfix/master.cf /etc/postfix/master.cf.bak 
  cat <<EOF > /etc/postfix/master.cf
smtp      inet  n       -       y       -       -       smtpd

# SERVICIO: Habilita el puerto 587 (submission) para que los clientes de correo 
# (Outlook, Thunderbird) envíen correos de forma encriptada y autenticada.
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

  cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf.bak 
  cat <<EOF > /etc/dovecot/conf.d/10-ssl.conf
# Requerir SSL y definir rutas de certificados
# SEGURIDAD: Impide las conexiones IMAP/POP3 en texto plano. Obliga a usar túneles cifrados.
ssl = required
ssl_server_cert_file = /etc/ssl/certs/${HOSTNAME_CORREO}.crt
ssl_server_key_file = /etc/ssl/private/${HOSTNAME_CORREO}.key
ssl_server_ca_file = /etc/ssl/certs/ca-root.crt

# Protocolo mínimo aceptado
# SEGURIDAD: Deshabilita protocolos obsoletos (SSLv2, SSLv3, TLS 1.0/1.1) propensos a ataques.
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

# RELACIÓN CRUZADA: Este bloque crea el socket UNIX (/var/spool/postfix/private/auth)
# mediante el cual Postfix se comunica con Dovecot para verificar usuarios y contraseñas.
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
}

creacion_usuarios_maildir() {
  log_info "Creando Usuario y Maildir"
  if ! id "$USUARIO_CORREO" &>/dev/null; then
    
    # SEGURIDAD: '-s /sbin/nologin' garantiza que el usuario solo pueda usar servicios 
    # de correo, pero no pueda abrir una terminal SSH en el servidor.
    useradd -m -s /sbin/nologin -c "Usuario de Correo" "$USUARIO_CORREO" 
    echo "$USUARIO_CORREO:$PASSWORD_CORREO" | chpasswd

    # SERVICIO: Creación manual de la estructura Maildir (new, cur, tmp)
    mkdir -p /home/"$USUARIO_CORREO"/Maildir/{new,cur,tmp} 
    
    # SEGURIDAD: Se asegura la privacidad aislando los correos al dueño de la cuenta.
    chown -R "$USUARIO_CORREO":"$USUARIO_CORREO" /home/"$USUARIO_CORREO"/Maildir/ 
    chmod -R 700 /home/"$USUARIO_CORREO"/Maildir/
  else
    log_info "El usuario $USUARIO_CORREO ya existe, omitiendo creación."
  fi
}

configuracion_red() {
  # SERVICIO: Fija la configuración IP para asegurar que el servidor de correo
  # siempre sea localizable en la misma dirección por el DNS.
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
}

habilitar_servicios() {
  log_info "Reiniciando y habilitando servicios Postfix y Dovecot"
  systemctl restart postfix dovecot 
  systemctl enable postfix dovecot
  systemctl restart postfix dovecot 
  systemctl enable postfix dovecot
  systemctl status postfix dovecot
}

mensaje_final() {
  echo "=========================================================="
  echo "¡Configuración de Postfix y Dovecot completada exitosamente!"
  echo "=========================================================="
}

#========================================================================
#EJECUCIÓN PRINCIPAL
#======================================================================== 
verificar_privilegios
recoleccion_variables
preparacion_sistema
actualizar_instalar_paquetes
gestion_certificados
configuracion_postfix_dovecot
creacion_usuarios_maildir
configuracion_red
habilitar_servicios
mensaje_final