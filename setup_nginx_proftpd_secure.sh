#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Automatización de Infraestructura Web (Nginx) y FTP Seguro (ProFTPD)
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

# SEGURIDAD: Abortar la ejecución ante fallos en comandos o tuberías (pipelines)
# evita despliegues parciales que podrían dejar los servicios en un estado vulnerable.
set -eo pipefail

log_info() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

# ==============================================================================
# FASE 0: VERIFICACIÓN DE PRIVILEGIOS
# ==============================================================================
# SEGURIDAD: La manipulación de llaves criptográficas TLS y la vinculación de 
# servicios a puertos privilegiados (80, 443, 21) exige permisos de superusuario.
if [ "$EUID" -ne 0 ]; then
  log_error "Error: Este script debe ser ejecutado como root."
  exit 1
fi

backup_file() {
  # SERVICIO: Garantiza la resiliencia de los archivos de configuración base.
  # Facilita el rollback en caso de corrupción durante la inyección de parámetros.
  local FILE="$1"
  if [ -f "$FILE" ]; then
    cp "$FILE" "${FILE}.bak"
    log_info "Copia de seguridad creada para $FILE"
  fi
}

# ==============================================================================
# FASE 1: RECOLECCIÓN DE VARIABLES
# ==============================================================================
recoleccion_variables() {
    log_info "--- Configuración Base ---"
    read -r -p "Nombre del servidor (HOSTNAME, ej. gamma): " HOSTNAME
    read -r -p "Dominio principal (DOMINIO_WEB, ej. xeon.cr): " DOMINIO_WEB
    read -r -p "Nombre de dominio completamente calificado (FQDN, ej. gamma.xeon.cr): " FQDN
    read -r -p "Dirección IP estática del servidor (ej. 192.168.106.3): " IP_SERVIDOR
    read -r -p "Máscara de red (ej. 255.255.255.0): " MASCARA_RED
    read -r -p "Puerta de enlace (Gateway, ej. 192.168.106.254): " PUERTA_ENLACE
    read -r -p "Dirección IP del DNS (ej. 192.168.106.1): " IP_DNS
    read -r -p "Interfaz de red principal (ej. enp0s3): " INTERFAZ_RED
    read -r -p "Ruta raíz web (ej. /var/www/xeon.cr): " RUTA_RAIZ_WEB
    read -r -p "Usuario FTP para administrar la web (ej. webadmin): " USUARIO_FTP

    log_info "--- Rutas de Certificados y Llaves ---"
    read -r -p "Ruta absoluta de la llave SSL (.key): " RUTA_LLAVE
    read -r -p "Ruta absoluta del certificado CA (.crt): " RUTA_CERT_CA
    read -r -p "Ruta absoluta del certificado SSL (.crt): " RUTA_CERT_SSL

    # RELACIÓN CRUZADA: Estandarización de la nomenclatura de los activos criptográficos.
    # Estos nombres unificados serán consumidos concurrentemente por Nginx y ProFTPD.
    DEST_LLAVE="${DOMINIO_WEB}.key"
    DEST_CERT_CA="ca_${DOMINIO_WEB}.crt"
    DEST_CERT_SSL="${DOMINIO_WEB}.crt"
}

# ==============================================================================
# FASE 2: APROVISIONAMIENTO DE PAQUETES
# ==============================================================================
instalar_paquetes() {
    log_info "Actualizando repositorios e instalando paquetes base..."
    apt update && apt upgrade -y
    
    # SERVICIO: Nginx actuará como el servidor web de alto rendimiento.
    log_info "Instalando Nginx..."
    apt install nginx -y
    
    # SERVICIO: ProFTPD gestionará la ingesta de archivos. El módulo mod-crypto 
    # es obligatorio para implementar la capa de seguridad FTPS (TLS).
    log_info "Instalando ProFTPD y módulo TLS..."
    apt install proftpd-basic proftpd-mod-crypto -y
}

# ==============================================================================
# FASE 3: DESPLIEGUE Y CONFIGURACIÓN DE NGINX
# ==============================================================================
configurar_nginx() {
    mkdir -p "$RUTA_RAIZ_WEB/html"
    log_info "Creando archivo index.html de prueba..."
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
    <div class="footer">Desplegado y configurado.</div>
</body>
</html>
EOF

    log_info "Transfiriendo y asegurando certificados..."
    # SEGURIDAD: Control de acceso estricto sobre la llave privada (600). Un compromiso 
    # de este activo permite la suplantación de la identidad del servidor.
    cp "$RUTA_LLAVE" "/etc/ssl/private/$DEST_LLAVE"
    chown root:root "/etc/ssl/private/$DEST_LLAVE"
    chmod 600 "/etc/ssl/private/$DEST_LLAVE"

    cp "$RUTA_CERT_CA" "/etc/ssl/certs/$DEST_CERT_CA"
    chown root:root "/etc/ssl/certs/$DEST_CERT_CA"
    chmod 644 "/etc/ssl/certs/$DEST_CERT_CA"

    cp "$RUTA_CERT_SSL" "/etc/ssl/certs/$DEST_CERT_SSL"
    chown root:root "/etc/ssl/certs/$DEST_CERT_SSL"
    chmod 644 "/etc/ssl/certs/$DEST_CERT_SSL"

    log_info "Creando Virtual Host para Nginx..."
    cat <<EOF > "/etc/nginx/sites-available/$DOMINIO_WEB"
# SERVICIO: Redirección obligatoria (301) en el puerto 80 para garantizar que 
# todas las conexiones transiten por el túnel cifrado.
server {
    listen 80;
    server_name $DOMINIO_WEB www.$DOMINIO_WEB;
    return 301 https://\$host\$request_uri;
}

# SERVICIO: Bloque principal TLS. Habilita los protocolos seguros modernos.
server {
    listen 443 ssl;
    server_name $DOMINIO_WEB www.$DOMINIO_WEB;
    root $RUTA_RAIZ_WEB/html;
    index index.html index.htm;

    ssl_certificate /etc/ssl/certs/$DEST_CERT_SSL;
    ssl_certificate_key /etc/ssl/private/$DEST_LLAVE;
    
    # SEGURIDAD: Cifrados restrictivos (HIGH) e inhabilitación de protocolos obsoletos.
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # SEGURIDAD: Mitigación de ataques de tipo Clickjacking y MIME-sniffing.
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
}
EOF

    log_info "Habilitando sitio en Nginx..."
    ln -sf "/etc/nginx/sites-available/$DOMINIO_WEB" /etc/nginx/sites-enabled/
}

# ==============================================================================
# FASE 4: GESTIÓN DE USUARIOS Y PERMISOS
# ==============================================================================
usuario_y_permisos() {
    log_info "Creando usuario FTP..."
    # SEGURIDAD: Asignación de shell /usr/sbin/nologin. Previene que el administrador 
    # web escale su acceso hacia una sesión interactiva (SSH/TTY) en el sistema.
    useradd -m -d "$RUTA_RAIZ_WEB" -s /usr/sbin/nologin "$USUARIO_FTP"
    
    log_info "Por favor, asigne una contraseña para el usuario FTP ($USUARIO_FTP):"
    passwd "$USUARIO_FTP"

    log_info "Ajustando permisos del directorio web..."
    # RELACIÓN CRUZADA: El propietario del directorio es el usuario FTP (para subidas), 
    # pero el grupo es 'www-data', permitiendo al demonio Nginx leer el contenido.
    chown -R "$USUARIO_FTP":www-data "$RUTA_RAIZ_WEB"
    chmod -R 775 "$RUTA_RAIZ_WEB"
}

# ==============================================================================
# FASE 5: DESPLIEGUE Y CONFIGURACIÓN DE PROFTPD
# ==============================================================================
configurar_proftpd() {
    log_info "Configurando proftpd.conf..."
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

# SEGURIDAD: Enjaulamiento (chroot) estricto. El usuario FTP no podrá ascender 
# más allá de su directorio de inicio definido en /etc/passwd.
DefaultRoot ~

# SEGURIDAD: Necesario para permitir autenticación a cuentas con shell falso (nologin).
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

# SEGURIDAD: Lista blanca explícita. Solo el usuario dedicado puede iniciar sesión.
<Limit LOGIN>
  AllowUser $USUARIO_FTP
  DenyAll
</Limit>

Include /etc/proftpd/conf.d/
EOF

    log_info "Configurando tls.conf de ProFTPD..."
    cat <<EOF > /etc/proftpd/tls.conf
<IfModule mod_tls.c>
    TLSEngine on
    TLSLog /var/log/proftpd/tls.log
    TLSProtocol TLSv1.2 TLSv1.3

    # RELACIÓN CRUZADA: ProFTPD consume exactamente los mismos activos criptográficos 
    # que fueron emplazados y asegurados en la fase de Nginx.
    TLSRSACertificateFile /etc/ssl/certs/$DEST_CERT_SSL
    TLSRSACertificateKeyFile /etc/ssl/private/$DEST_LLAVE
    TLSCACertificateFile /etc/ssl/certs/$DEST_CERT_CA

    TLSVerifyClient off
    
    # SEGURIDAD: Negación de conexiones FTP en texto plano. Obliga al cliente 
    # (ej. FileZilla) a negociar una sesión FTPS explícita antes de transferir datos.
    TLSRequired on
</IfModule>
EOF

    log_info "Habilitando mod_tls.c en modules.conf..."
    sed -i 's/^#\s*LoadModule mod_tls.c/LoadModule mod_tls.c/' /etc/proftpd/modules.conf
}

# ==============================================================================
# FASE 6: MUTACIÓN DE HOSTNAME Y CONFIGURACIÓN DE RED
# ==============================================================================
mutacion_hostname_red() {
    log_info "Configurando hostname..."
    # SERVICIO: Identidad base en memoria para los servicios internos.
    hostnamectl set-hostname "$HOSTNAME"

    log_info "Configurando /etc/hosts..."
    # RELACIÓN CRUZADA: Mapeo del FQDN local para que los servicios que auditan 
    # la máquina resuelvan correctamente la identidad sin depender del DNS.
    cat <<EOF > /etc/hosts
127.0.0.1       localhost
127.0.1.1       $FQDN   $HOSTNAME
EOF

    log_info "Configurando IP estática..."
    # SERVICIO: Transición de la interfaz hacia su direccionamiento de producción.
    cat <<EOF > /etc/network/interfaces
# Interfaz de red principal
allow-hotplug $INTERFAZ_RED
iface $INTERFAZ_RED inet static
    address $IP_SERVIDOR
    netmask $MASCARA_RED
    gateway $PUERTA_ENLACE
EOF

    log_info "Configurando resolución DNS..."
    cat <<EOF > /etc/resolv.conf
nameserver $IP_DNS
search $DOMINIO_WEB
EOF
}

# ==============================================================================
# FASE 7: VERIFICACIÓN DE SINTAXIS Y REINICIO
# ==============================================================================
verificar_sintaxis_reiniciar() {
    # SERVICIO: Validaciones de sintaxis preventivas (Dry-run). Evitan un reinicio 
    # destructivo en caso de anomalías tipográficas en los archivos de configuración.
    log_info "Verificando sintaxis de Nginx..."
    nginx -t

    log_info "Verificando sintaxis de ProFTPD..."
    proftpd -t

    log_info "Reiniciando servicios..."
    systemctl restart nginx
    systemctl restart proftpd

    log_info "¡Despliegue finalizado exitosamente!"
}

# ==============================================================================
# EJECUCIÓN PRINCIPAL
# ==============================================================================
recoleccion_variables
instalar_paquetes
configurar_nginx
usuario_y_permisos
configurar_proftpd
mutacion_hostname_red
verificar_sintaxis_reiniciar