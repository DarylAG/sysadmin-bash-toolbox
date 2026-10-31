#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Automatizar la instalación y configuración de Squid Proxy 
#            transparente con inspección HTTPS (SSL Bumping) e inyección 
#            de reglas de iptables.
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "   Automatización de Squid Proxy Transparente (SSL)       "
echo "=========================================================="

log_info () {

    echo -e "\e[32m[INFO]\e[0m $1"

}

log_error () {

    echo -e "\e[31m[ERROR]\e[0m $1"

}

verificar_privilegios() {

    log_info "Verificando privilegios de administrador..."
    if [[ $EUID -ne 0 ]]; then

       log_error "Este script requiere privilegios elevados. Ejecútalo como root o usando sudo."
       exit 1

    fi
}

recoleccion_variables () {

    log_info "Recolección de variables para la configuración de Squid..."
    HTTP_PORT_DEFAULT=3127
    HTTP_PORT_INTERCEPT_DEFAULT=3128
    HTTPS_PORT_DEFAULT=3129
    read -r -p "Ingrese el hostname del servidor proxy: " HOSTNAME
    read -r -p "Ingrese la ubicacion del certificado entidad raiz (CA): " CA_CERT_PATH
    read -r -p "Ingrese la ubicacion del certificado del servidor proxy: " SERVER_CERT_PATH
    read -r -p "Ingrese la ubicacion de la clave privada del servidor proxy: " SERVER_KEY_PATH
    read -r -p "Ingrese la ubicacion de la llave privada de la entidad raiz (CA): " CA_KEY_PATH
    read -r -p "Ingrese la red local (ejemplo: 192.168.1.0/24): " RED_LOCAL

    # Validación de variables vacías
    if [[ -z "$HOSTNAME" || -z "$CA_CERT_PATH" || -z "$SERVER_CERT_PATH" || -z "$SERVER_KEY_PATH" || -z "$CA_KEY_PATH" || -z "$RED_LOCAL" ]]; then
        
        log_error "Todos los campos son obligatorios para configurar el proxy."
        exit 1

    fi

    # Validación de existencia física de los certificados
    if [[ ! -f "$CA_CERT_PATH" || ! -f "$SERVER_CERT_PATH" || ! -f "$SERVER_KEY_PATH" || ! -f "$CA_KEY_PATH" ]]; then
        
        log_error "Uno o más archivos de certificado no existen en las rutas proporcionadas."
        exit 1

    fi
}

instalar_squid () {

    log_info "Instalando dependencias (Squid, OpenSSL, iptables)..."
    apt-get update && apt upgrade -y
    apt-get install -y squid squid-openssl iptables

}

gestion_certificado () {
    
    log_info "Gestionando certificados..."
    mkdir -p /etc/squid/certs
    cd /etc/squid/certs
    cp "$CA_CERT_PATH" ./ca.crt
    cp "$SERVER_CERT_PATH" ./server.crt
    cp "$SERVER_KEY_PATH" ./server.key
    cp "$CA_KEY_PATH" ./ca.key
    cat /etc/squid/certs/ca.crt /etc/squid/certs/ca.key > /etc/squid/certs/squid.pem
    chown -R proxy:proxy /etc/squid/certs
    chmod 755 /etc/squid/certs
    chmod 600 /etc/squid/certs/squid.pem

}

inicializar_base_datos () {
    
    log_info "Inicializando base de datos..."
    mkdir -p /var/lib/squid
    chown -R proxy:proxy /var/lib/squid
    
    # Prevención de sobreescritura (Idempotencia)
    if [[ ! -d "/var/lib/squid/ssl_db" ]]; then

        /usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
        chown -R proxy:proxy /var/lib/squid/ssl_db

    else

        log_info "La base de datos SSL ya existe, omitiendo creación."

    fi

}

configurar_squid () {
    
    log_info "Configurando Squid..."
    mkdir -p /etc/squid/backup

    # Solo hacer backup si el archivo original existe
    if [[ -f /etc/squid/squid.conf ]]; then

        cp /etc/squid/squid.conf /etc/squid/backup/squid.conf.bak
        
    fi

    cat <<EOF > /etc/squid/squid.conf
# ----------------------------------------------------------------------
# DEFINICIÓN DE REDES Y PUERTOS SEGUROS
# ----------------------------------------------------------------------
acl localnet src ${RED_LOCAL}    # Define tu red local
acl Safe_ports port 80          # http
acl Safe_ports port 443         # https
acl SSL_ports port 443          # https exclusivo

# Denegar peticiones y CONNECT a puertos no seguros
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# ----------------------------------------------------------------------
# REGLAS DE CONTROL DE ACCESO (HTTP_ACCESS)
# ----------------------------------------------------------------------
http_access allow localhost
http_access allow localnet
http_access deny all

# ----------------------------------------------------------------------
# PUERTOS Y SSL BUMPING (PROXY TRANSPARENTE)
# ----------------------------------------------------------------------
# Puerto base para Squid 6+ (evita advertencias)
http_port ${HTTP_PORT_DEFAULT}

# Intercepción HTTP transparente
http_port ${HTTP_PORT_INTERCEPT_DEFAULT} intercept

# Intercepción HTTPS transparente con certificados dinámicos
https_port ${HTTPS_PORT_DEFAULT} intercept ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=/etc/squid/certs/squid.pem

# Programa de gestión de base de datos SSL
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 4MB

# Reglas de inspección SSL (Paso 1, 2 y 3)
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump bump all

# ----------------------------------------------------------------------
# PARÁMETROS DE RED, CACHÉ Y SISTEMA
# ----------------------------------------------------------------------
maximum_object_size 4 MB
visible_hostname ${HOSTNAME}
shutdown_lifetime 3 seconds
EOF

}

reglas_firewall () {
    
    log_info "Configurando reglas de firewall..."
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port "${HTTP_PORT_INTERCEPT_DEFAULT}"
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "${HTTPS_PORT_DEFAULT}"

}

verificar_estado_squid () {
    
    log_info "Verificando estado de Squid..."
    squid -k parse
    systemctl restart squid
    systemctl enable squid
    echo "=========================================================="
    echo "¡Configuración de Squid Proxy completada exitosamente!"
    echo "=========================================================="
    systemctl status squid --no-pager

}

# ==============================================================================
# EJECUCIÓN PRINCIPAL
# ==============================================================================
verificar_privilegios
recoleccion_variables
instalar_squid
gestion_certificado
inicializar_base_datos
configurar_squid
reglas_firewall
verificar_estado_squid