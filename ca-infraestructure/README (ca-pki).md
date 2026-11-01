# 1. Convenciones y Variables
Para garantizar la correcta adaptabilidad de esta plantilla a cualquier entorno, se han reemplazado los valores estáticos por marcadores de posición. Antes de ejecutar los comandos, sustituya las siguientes variables por los valores reales de su infraestructura:

## Variables de Entorno y Nomenclatura

- **`<DIR_CA>`**: Ruta base del directorio de la CA (ej. `/home/administrator/ca` o `/root/ca`).

- **`<NOMBRE_CA>`**: Nombre del archivo base para la CA (ej. `root-ca` o `empresa-ca`).

- **`<NOMBRE_NODO>`**: Nombre del servicio o servidor a certificar (ej. `web`, `mail`, `proxy`).

- **`<IP_NODO>`**: Dirección IP del servidor para la extensión SAN.


## Variables de Identidad (Campos del Subject X.509)

- **`<PAIS>` (C - Country)**: Código de país de 2 letras bajo el estándar ISO 3166-1 alpha-2 (ej. `CR` para Costa Rica, `ES` para España).

- **`<ESTADO>` (ST - State or Province)**: Nombre completo del estado, provincia o región (ej. `Alajuela`, `Madrid`).

- **`<LOCALIDAD>` (L - Locality)**: Nombre de la ciudad o municipio.

- **`<ORGANIZACION>` (O - Organization)**: Nombre legal de la empresa o entidad operadora (ej. `empresa.com`).

- **`<DOMINIO>` (CN - Common Name)**: El Fully Qualified Domain Name (FQDN) principal del servidor o el nombre descriptivo de la CA (ej. `[www.empresa.com](https://www.empresa.com)` o `Empresa Root CA`).


# 2. Preparación del Entorno y Estructura de Directorios

**Acción:** Establecer la estructura de directorios segura requerida por OpenSSL para administrar la base de datos de certificados, números de serie y almacenar las llaves criptográficas con los permisos adecuados.

**Comando:**
Cambiar el hostname del servidor CA (Opcional pero recomendado para identificación)
```bash
hostnamectl set-hostname ca-server
```
Crear la estructura de directorios
```bash
mkdir -p <DIR_CA>/{private,certs,newcerts,csr}
```
Restringir el acceso a la carpeta de llaves privadas (solo lectura/escritura para el propietario)
```bash
chmod -v 700 <DIR_CA>/private
```

Inicializar la base de datos de certificados y el número de serie hexadecimal
```bash
touch <DIR_CA>/index
openssl rand -hex 16 > <DIR_CA>/serial
```

# 3. Archivo de Configuración de la CA (`root-ca.conf`)

Cree el archivo `<DIR_CA>/root-ca.conf` con el siguiente contenido optimizado. Este archivo define las políticas de firma y las extensiones criptográficas necesarias para la CA y los certificados emitidos.
```bash
[ ca ]
# Define la sección por defecto para el comando 'ca'
default_ca = CA_default

[ CA_default ]
# Rutas de la estructura de directorios
dir           = <DIR_CA>
certs         = $dir/certs
new_certs_dir = $dir/newcerts
database      = $dir/index
serial        = $dir/serial
RANDFILE      = $dir/private/.rand

# Archivos de la CA (Llave privada y Certificado público)
certificate   = $dir/certs/<NOMBRE_CA>.crt
private_key   = $dir/private/<NOMBRE_CA>.key

# Parámetros criptográficos y de emisión
default_md    = sha256
name_opt      = ca_default
cert_opt      = ca_default
default_days  = 365
preserve      = no
policy        = policy_strict

[ policy_strict ]
# Requisitos de los campos del Subject para que la CA firme el certificado
countryName             = supplied
stateOrProvinceName     = supplied
organizationName        = supplied
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
# Parámetros para la generación de solicitudes (CSR)
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
# Plantilla interactiva de campos (Ignorada si se usa prompt=no en el CSR)
countryName         = Country Name (2 letter code)
stateOrProvinceName = State or Province Name
localityName        = Locality Name
organizationName    = Organization Name
commonName          = Common Name

[ v3_ca ]
# Extensiones obligatorias para un certificado de Autoridad Certificadora
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
# Extensiones estándar para certificados de servidor final
basicConstraints       = CA:FALSE
nsCertType             = server
nsComment              = "Certificado Digital para Servidor Interno"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
```

## 4. Generación de la Llave y Certificado Root CA

**Acción:** Generar la llave privada de la CA utilizando cifrado AES-256 y un tamaño de 4096 bits para máxima seguridad. Luego, restringir los permisos del archivo.

**Comando:**
```bash
cd <DIR_CA>
openssl genrsa -aes256 -out <DIR_CA>/private/<NOMBRE_CA>.key 4096
chmod 400 <DIR_CA>/private/<NOMBRE_CA>.key
```

**Acción:** Generar el certificado raíz autofirmado (Root CA) utilizando la configuración definida. Se establece una validez extensa (ej. 3650 días / 10 años) y se aplica la extensión `v3_ca` para habilitar sus funciones como entidad certificadora.

**Comando:**
```bash
openssl req -config <DIR_CA>/root-ca.conf \
  -key <DIR_CA>/private/<NOMBRE_CA>.key \
  -new -x509 -days 3650 -sha256 -extensions v3_ca \
  -out <DIR_CA>/certs/<NOMBRE_CA>.crt
```

## 5. REQUISITO CRÍTICO: Certificado PEM sin contraseña para Squid Proxy (SSL-Bump)

Para inspección SSL/TLS (SSL Bumping) en Squid Proxy transparente, el servicio requiere que la llave privada de la CA no esté cifrada con contraseña (unencrypted) para poder firmar certificados en memoria dinámicamente. Además, Squid comúnmente requiere la llave privada y el certificado combinados en un único archivo `.pem`.

**Acción 1:** Extraer una copia sin contraseña (descifrada) de la llave privada de la CA. Se le solicitará la frase de paso de la llave original.

**Comando:**
```bash
openssl rsa -in <DIR_CA>/private/<NOMBRE_CA>.key -out <DIR_CA>/private/<NOMBRE_CA>-sinpass.key
# Proteger la llave sin contraseña rigurosamente
chmod 400 <DIR_CA>/private/<NOMBRE_CA>-sinpass.key
```

**Acción 2:** Concatenar la llave privada descifrada y el certificado público de la CA en un archivo `.pem` unificado.

**Comando:**
```bash
cat <DIR_CA>/private/<NOMBRE_CA>-sinpass.key <DIR_CA>/certs/<NOMBRE_CA>.crt > <DIR_CA>/certs/<NOMBRE_CA>-squid-bundle.pem
chmod 400 <DIR_CA>/certs/<NOMBRE_CA>-squid-bundle.pem
```

## 6. Generación de Certificados de Servidor (Nodos)

Este proceso debe repetirse para cada servicio (Web, Correo, Proxy, etc.) adaptando las variables.

### 6.1. Archivo de Configuración CSR del Nodo (`<NOMBRE_NODO>-csr.conf`)

Cree un archivo específico para el nodo en `<DIR_CA>/csr/<NOMBRE_NODO>-csr.conf`. Este enfoque inyecta el _Subject Alternative Name (SAN)_ directamente en la petición, lo cual es un requisito estricto de los navegadores modernos.
```bash
[ req ]
default_bits       = 2048
default_md         = sha256
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[ req_distinguished_name ]
# Reemplazar con variables reales
countryName            = <PAIS>
stateOrProvinceName    = <ESTADO>
localityName           = <LOCALIDAD>
organizationName       = <ORGANIZACION>
commonName             = <DOMINIO>

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
# Nombres alternativos (FQDN, hostnames cortos y Direcciones IP)
DNS.1 = <DOMINIO>
DNS.2 = www.<DOMINIO>
DNS.3 = <NOMBRE_NODO>
IP.1  = <IP_NODO>

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
```

### 6.2. Creación y Firma del Certificado del Nodo

**Acción:** Generar la llave privada (2048 bits) para el servidor final.

**Comando:**
```bash
openssl genrsa -out <DIR_CA>/private/<NOMBRE_NODO>.key 2048
```

**Acción:** Generar la Solicitud de Firma de Certificado (CSR) utilizando el archivo de configuración personalizado que incluye las extensiones SAN.

**Comando:**
```bash
openssl req -new -key <DIR_CA>/private/<NOMBRE_NODO>.key -sha256 \
  -out <DIR_CA>/csr/<NOMBRE_NODO>.csr \
  -config <DIR_CA>/csr/<NOMBRE_NODO>-csr.conf
```

**Acción:** Firmar el certificado del nodo utilizando la Root CA. Se fuerza la inclusión de las extensiones SAN (`req_ext`) pasándolas directamente desde el archivo `.conf` del nodo mediante `-extfile`.

**Comando:**
```bash
openssl ca -config <DIR_CA>/root-ca.conf -notext \
  -in <DIR_CA>/csr/<NOMBRE_NODO>.csr \
  -out <DIR_CA>/certs/<NOMBRE_NODO>.crt \
  -extensions req_ext \
  -extfile <DIR_CA>/csr/<NOMBRE_NODO>-csr.conf -batch[cite: 1]
```

## 7. Verificación y Troubleshooting

### Comandos de Verificación

Para auditar la correcta generación de los elementos criptográficos, utilice los siguientes comandos de inspección en texto plano:

- Verificar un Certificado Público (.crt / .pem):
```bash
openssl x509 -text -noout -in <DIR_CA>/certs/<NOMBRE_NODO>.crt
```

- Verificar una Solicitud de Firma (CSR):
```bash
openssl req -text -noout -verify -in <DIR_CA>/csr/<NOMBRE_NODO>.csr
```

- Verificar Extensiones SAN Específicas:
```bash
openssl x509 -text -noout -in <DIR_CA>/certs/<NOMBRE_NODO>.crt | grep -A 2 "Subject Alternative Name"
```

- Comprobar Integridad (Módulo Matemático):
```bash
openssl rsa -noout -modulus -in <DIR_CA>/private/<NOMBRE_NODO>.key | openssl md5 openssl x509 -noout -modulus -in <DIR_CA>/certs/<NOMBRE_NODO>.crt | openssl md5
```

### Troubleshooting Común

- **Navegador arroja "ERR_CERT_COMMON_NAME_INVALID":** Chrome y navegadores modernos ignoran el campo _Common Name (CN)_. Si aparece este error, el certificado se firmó sin la extensión _Subject Alternative Name (SAN)_. Verifique el paso 6.2 y asegúrese de incluir el flag `-extfile`.


- **Navegador arroja "ERR_CERT_AUTHORITY_INVALID":** El certificado público del servidor fue verificado exitosamente, pero el sistema operativo o navegador cliente no confía en quien lo emitió. Debe instalar `ca.crt` en el almacén de "Trusted Root Certification Authorities" del cliente.

 
- **Error de OpenSSL "TXT_DB error number 2":** Significa que está intentando firmar un certificado con un _Subject_ idéntico a uno previamente firmado. Debe revocar el anterior o cambiar el requerimiento `unique_subject = no` en el archivo `index.attr`.


## 8. Funciones Avanzadas y Próximos Pasos

Para evolucionar esta CA a un modelo Enterprise estándar, se recomienda implementar las siguientes fases:

1. **Autoridades Intermedias (Intermediate CAs):** La mejor práctica de seguridad dicta mantener la Root CA apagada/offline. Se debe generar una Intermediate CA firmada por la Root, y utilizar la Intermedia para emitir los certificados del día a día.

2. **Listas de Revocación de Certificados (CRL):** Configurar y habilitar la generación periódica de archivos `.crl` para informar a los clientes de certificados comprometidos antes de su fecha de expiración.

3. **Online Certificate Status Protocol (OCSP):** Implementar un responder OCSP para validaciones de revocación en tiempo real, lo cual es más eficiente en redes grandes que la descarga de archivos CRL pesados.

4. **Automatización de Despliegue:** Empaquetar el certificado raíz público mediante GPOs de Active Directory o herramientas como Ansible para distribuirlo en el _Trust Store_ de todos los endpoints corporativos.