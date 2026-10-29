#!/bin/bash
# Autor: Daril Arias
# Fecha: 10/2026

echo "=========================================================="
echo "   Automatización de Autoridad Certificadora (CA)         "
echo "=========================================================="

# Consultar valores variables al usuario
read -r -p "Ruta base para la CA (ej. /home/administrator/ca): " CA_DIR
read -r -p "Código de País (2 letras, ej. CR): " VAL_C
read -r -p "Estado o Provincia (ej. Alajuela): " VAL_ST
read -r -p "Localidad (ej. Alajuela): " VAL_L
read -r -p "Nombre de la Organización (ej. xeon.cr): " VAL_O
read -r -p "Nombre Común de la CA (ej. delta-ca): " VAL_CN

echo "Creando estructura de directorios..."
mkdir -p "$CA_DIR"/certs "$CA_DIR"/newcerts "$CA_DIR"/private
chmod 700 "$CA_DIR"/private
touch "$CA_DIR"/index
echo 1000 > "$CA_DIR"/serial

echo "Generando archivo de configuración root-ca.conf..."
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
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints  = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Certificado Digital para Servidores XEON"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage  = serverAuth
EOF

echo "Generando llave privada de la CA..."
openssl genrsa -out "$CA_DIR/private/${VAL_CN}.key" 4096

echo "Generando certificado Raíz de la CA..."
openssl req -config "$CA_DIR/root-ca.conf" -key "$CA_DIR/private/${VAL_CN}.key" \
  -new -x509 -days 3650 -sha256 -extensions v3_ca \
  -out "$CA_DIR/certs/${VAL_CN}.crt" -subj "/C=$VAL_C/ST=$VAL_ST/L=$VAL_L/O=$VAL_O/CN=$VAL_CN"

echo "Generando plantilla para clientes (template-csr.conf)..."
cat <<EOF > "$CA_DIR/template-csr.conf"
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

echo "=========================================================="
echo "¡Configuración completada exitosamente!"
echo "Archivos generados:"
echo " - CA Config: $CA_DIR/root-ca.conf"
echo " - CA Key:    $CA_DIR/private/${VAL_CN}.key"
echo " - CA Cert:   $CA_DIR/certs/${VAL_CN}.crt"
echo " - Template:  $CA_DIR/template-csr.conf"
echo "=========================================================="