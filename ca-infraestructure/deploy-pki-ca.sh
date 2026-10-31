#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Automatizar el despliegue de una Autoridad Certificadora (CA) local 
#            y estructurar su base de datos para emitir, firmar y gestionar 
#            certificados TLS/SSL en servicios de infraestructura interna.
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "   Automatización de Autoridad Certificadora (CA)         "
echo "=========================================================="

log_info () {
  echo -e "\n\e[32m[INFO]\e[0m $1"
}

verificar_dependencias() {
  log_info "Verificando dependencias del sistema..."
  
  # SERVICIO: OpenSSL es el motor criptográfico subyacente que gestionará 
  # todo el ciclo de vida de los certificados (creación, firma y revocación).
  if ! command -v openssl &> /dev/null; then
    echo -e "\e[31m[ERROR]\e[0m OpenSSL no está instalado en este sistema."
    echo "Por favor, instálalo ejecutando: sudo apt-get install openssl"
    exit 1
  fi
}

recoleccion_variables() {
  log_info "Recolección de variables para la CA..."
  read -r -p "Ruta base para la CA (ej. /home/administrator/ca): " CA_DIR
  read -r -p "Código de País (2 letras, ej. CR): " VAL_C
  read -r -p "Estado o Provincia (ej. Alajuela): " VAL_ST
  read -r -p "Localidad (ej. Alajuela): " VAL_L
  read -r -p "Nombre de la Organización (ej. xeon.cr): " VAL_O
  read -r -p "Nombre Común de la CA (ej. delta-ca): " VAL_CN
  
  if [[ -z "$CA_DIR" || -z "$VAL_CN" ]]; then
    echo -e "\e[31m[ERROR]\e[0m La ruta de la CA y el Nombre Común son obligatorios."
    exit 1
  fi
}

estructura_directorios() {
  log_info "Creando estructura de directorios para la CA..."
  
  # SERVICIO: 'newcerts' almacenará una copia automática de cada certificado emitido.
  mkdir -p "$CA_DIR"/certs "$CA_DIR"/newcerts "$CA_DIR"/private
  
  # SEGURIDAD: El directorio 'private' alojará la llave privada (root key) de la CA. 
  # Los permisos 700 evitan que usuarios no autorizados puedan comprometer la PKI.
  chmod 700 "$CA_DIR"/private
  
  # SERVICIO: 'index' actúa como la base de datos de texto plano donde OpenSSL 
  # registrará el estado (Válido, Revocado, Expirado) de cada certificado.
  touch "$CA_DIR"/index

  # SERVICIO: 'serial' lleva el control secuencial del número de serie que se asignará 
  # al próximo certificado emitido. Evita colisiones de identificadores.
  if [ ! -f "$CA_DIR/serial" ]; then
    echo 1000 > "$CA_DIR/serial"
  fi
}

generar_configuracion_ca() {
  log_info "Generando archivo de configuración root-ca.conf..."
  
  # SERVICIO: Inyección de la configuración maestra que dictará cómo opera la CA.
cat <<EOF > "$CA_DIR/root-ca.conf"
[ ca ]
default_ca = CA_default

[ CA_default ]
dir = $CA_DIR
certs = \$dir/certs
new_certs_dir = \$dir/newcerts
database = \$dir/index
serial = \$dir/serial
RANDFILE = \$dir/private/.rand
# SERVICIO: 'copy_extensions' permite que los certificados cliente hereden las extensiones 
# de subjectAltName (SAN) definidas en sus respectivas solicitudes (CSR).
copy_extensions = copy

certificate = \$dir/certs/${VAL_CN}.crt
private_key = \$dir/private/${VAL_CN}.key

default_md = sha256
name_opt = ca_default
cert_opt = ca_default
default_days = 365
preserve = no
policy = policy_strict

[ policy_strict ]
# SEGURIDAD: La política estricta obliga a que los certificados solicitados coincidan 
# en País, Estado y Organización con los de la CA para evitar firmas falsas o ajenas.
countryName = supplied
stateOrProvinceName = supplied
organizationName = supplied
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
string_mask = utf8only
default_md = sha256
x509_extensions = server_cert

[ req_distinguished_name ]
countryName = Country Name (2 letter code)
stateOrProvinceName = State or Province Name
localityName = Locality Name
organizationName = Organization Name
organizationalUnitName = Organizational Unit Name
commonName = Common Name
emailAddress = Email Address

countryName_default = $VAL_C
stateOrProvinceName_default = $VAL_ST
localityName_default = $VAL_L
organizationName_default = $VAL_O
commonName_default = $VAL_CN

[ v3_ca ]
# SEGURIDAD: 'basicConstraints = CA:TRUE' es el atributo más crítico. Indica a los navegadores 
# y sistemas operativos que este certificado tiene autoridad legal para firmar a otros.
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints  = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
# SERVICIO: Perfil para certificados de cliente o correo (MTLS / S/MIME).
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
# SERVICIO: Perfil para servidores (Web, Correo, Proxy). CA:FALSE evita que un servidor 
# vulnerado pueda emitir nuevos certificados haciéndose pasar por la CA principal.
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Certificado Digital para Servidores XEON"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
# RELACIÓN CRUZADA: 'serverAuth' es requerido por navegadores modernos para validar HTTPS.
extendedKeyUsage  = serverAuth
EOF
}

generar_llave_y_certificado_ca() {
  log_info "Generando llave privada y certificado raíz de la CA..."
  
  # SEGURIDAD: Se utiliza RSA de 4096 bits para la CA raíz, garantizando resistencia 
  # a la fuerza bruta durante los próximos años (estándar recomendado superior a 2048).
  openssl genrsa -out "$CA_DIR/private/${VAL_CN}.key" 4096
  chmod 600 "$CA_DIR/private/${VAL_CN}.key"
  
  log_info "Generando certificado Raíz de la CA..."
  # SERVICIO: Emisión del certificado autofirmado (raíz) válido por 10 años (3650 días).
  # '-extensions v3_ca' inyecta los permisos de Autoridad Certificadora definidos arriba.
  openssl req -config "$CA_DIR/root-ca.conf" -key "$CA_DIR/private/${VAL_CN}.key" \
  -new -x509 -days 3650 -sha256 -extensions v3_ca \
  -out "$CA_DIR/certs/${VAL_CN}.crt" -subj "/C=$VAL_C/ST=$VAL_ST/L=$VAL_L/O=$VAL_O/CN=$VAL_CN"
}

generar_plantilla_certificado() {
  log_info "Generando plantilla para clientes (template-csr.conf)..."
  
  # RELACIÓN CRUZADA: Esta plantilla es la que usarán los administradores de los 
  # servidores (ej. Nginx, Postfix) para solicitar un certificado a esta CA.
  cat <<EOF > "$CA_DIR/template-csr.conf"
#
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no
default_md         = sha256

[ req_distinguished_name ]
countryName            = $VAL_C
stateOrProvinceName    = $VAL_ST
localityName           = $VAL_L
organizationName       = $VAL_O
commonName             = REEMPLAZAR_POR_CN

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
# RELACIÓN CRUZADA: El atributo SAN (Subject Alternative Name) es estrictamente requerido 
# por Chrome/Edge/Firefox. Ya no basta con el 'Common Name' para evitar errores de seguridad.
DNS.1 = REEMPLAZAR_POR_CN
DNS.2 = www.REEMPLAZAR_POR_CN
IP.1  = 192.168.1.X

####################################################################
# EJEMPLOS DE CONFIGURACIÓN POR SERVICIO
####################################################################
#
# --- EJEMPLO: Servidor de Correo (beta) ---
# [ req_distinguished_name ]
# countryName            = CR
# stateOrProvinceName    = Alajuela
# organizationName       = xeon.cr
# commonName             = beta.xeon.cr
# [ alt_names ]
# DNS.1 = beta.xeon.cr
# DNS.2 = mail.xeon.cr
# DNS.3 = smtp.xeon.cr
# DNS.4 = imap.xeon.cr
# IP.1  = 192.168.1.2
#
# --- EJEMPLO: Servidor Web (gamma) ---
# [ req_distinguished_name ]
# countryName            = CR
# stateOrProvinceName    = Alajuela
# organizationName       = xeon.cr
# commonName             = gamma.xeon.cr
# [ alt_names ]
# DNS.1 = gamma.xeon.cr
# DNS.2 = www.xeon.cr
# DNS.3 = xeon.cr
# DNS.4 = gamma
# IP.1  = 192.168.1.3
#
# --- EJEMPLO: Servidor Proxy (iota) ---
# [ req_distinguished_name ]
# countryName            = CR
# stateOrProvinceName    = Alajuela
# localityName           = Alajuela
# organizationName       = xeon.cr
# commonName             = iota.xeon.cr
# [ alt_names ]
# DNS.1 = iota.xeon.cr
# DNS.2 = iota
# IP.1  = 192.168.106.4

####################################################################
# COMANDOS PARA GENERAR Y FIRMAR EL CERTIFICADO
####################################################################
# 1. Generar la llave privada del servidor:
# openssl genrsa -out SERVIDOR.key 2048
#
# 2. Generar el Certificate Signing Request (CSR):
# openssl req -new -key SERVIDOR.key -config ESTE_ARCHIVO.conf -out SERVIDOR.csr
#
# 3. Firmar el certificado con la CA (Ejecutar desde el directorio base de la CA):
# openssl ca -config root-ca.conf -extensions server_cert -days 365 -notext -md sha256 -in SERVIDOR.csr -out certs/SERVIDOR.crt
#
# 4. Generar formato PEM (Unificar llave y certificado para Squid Proxy, HAProxy, etc.):
# cat certs/SERVIDOR.crt SERVIDOR.key > certs/SERVIDOR.pem
EOF
}

mensaje_final() {
  log_info "Proceso de configuración de la CA completado."
  echo "=========================================================="
  echo "¡Configuración completada exitosamente!"
  echo "Archivos generados:"
  echo " - CA Config: $CA_DIR/root-ca.conf"
  echo " - CA Key:    $CA_DIR/private/${VAL_CN}.key"
  echo " - CA Cert:   $CA_DIR/certs/${VAL_CN}.crt"
  echo " - Template:  $CA_DIR/template-csr.conf"
  echo "=========================================================="
}

verificar_dependencias
recoleccion_variables
estructura_directorios
generar_configuracion_ca
generar_llave_y_certificado_ca
generar_plantilla_certificado
mensaje_final