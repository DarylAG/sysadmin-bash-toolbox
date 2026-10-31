# Configuración de Squid Proxy Transparente con SSL Bumping

## Convenciones y Variables

Antes de iniciar, identifica y sustituye las siguientes variables en los comandos y archivos de configuración según tu entorno:

- `<HOSTNAME>`: Nombre del servidor proxy (ej. proxy-server).

- `<RED_LOCAL>`: Rango de tu red local en formato CIDR (ej. 192.168.100.0/24).    

- `<IP_PROXY>`: Dirección IP asignada a la interfaz interna del servidor Squid.

- `<PUERTO_HTTP>`: Puerto de escucha base e intercepción HTTP, por defecto `3128`.

- `<PUERTO_HTTPS>`: Puerto de intercepción HTTPS, por defecto `3129`.

- `<NOMBRE_CA>`: Nombre base de los archivos de tu Autoridad Certificadora (ej. `ca-interna`).

## Fase 1: Preparación del Sistema e Instalación

Configura el nombre del host y asegúrate de que el sistema esté actualizado antes de instalar los paquetes necesarios.

Establecer el nombre de host:
```bash
hostnamectl set-hostname <HOSTNAME>
```

Actualizar repositorios e instalar Squid y utilidades de firewall:
```bash
apt update && apt upgrade -y
apt install squid iptables squid-openssl -y
```

## Fase 2: Gestión de Certificados para SSL Bumping

Para que Squid intercepte tráfico cifrado (HTTPS), debe actuar como una Autoridad Certificadora (CA) para generar certificados dinámicos. Es obligatorio combinar el certificado público y la clave privada sin contraseña en un único archivo `.pem`.

1. Posiciónate en el directorio de certificados de Squid:
```bash
mkdir -p /etc/squid/certs
cd /etc/squid/certs/
```

2. Genera el archivo `.pem` concatenando el certificado (`.crt`) y la llave privada (`.key`):
```bash
cat <NOMBRE_CA>.crt <NOMBRE_CA>.key > <NOMBRE_CA>.pem
```

3. Ajusta los permisos de seguridad (crítico para Squid):
```bash
chown -R proxy:proxy /etc/squid/certs
chmod 755 /etc/squid/certs
chmod 600 /etc/squid/certs/<NOMBRE_CA>.pem
```

## Fase 3: Inicialización de la Base de Datos SSL

Squid requiere un directorio para almacenar los certificados generados dinámicamente para cada sitio web.

1. Crea la estructura y asigna permisos:
```bash
mkdir -p /var/lib/squid
chown -R proxy:proxy /var/lib/squid
```

2. Inicializa la base de datos `ssl_db` (tamaño ajustado a 4MB):
```bash
/usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
chown -R proxy:proxy /var/lib/squid/ssl_db
```

## Fase 4: Configuración de Squid (`squid.conf`)

Respalda el archivo de configuración original:
```bash
mkdir -p /etc/squid/backup
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
mv /etc/squid/*.bak /etc/squid/backup/
```

Edita el archivo de configuración limpio:
```bash
nano /etc/squid/squid.conf
```

```bash
# ----------------------------------------------------------------------
# DEFINICIÓN DE REDES Y PUERTOS SEGUROS
# ----------------------------------------------------------------------
acl localnet src <RED_LOCAL>    # Define tu red local
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
http_port <PUERTO_HTTP>

# Intercepción HTTP transparente
http_port <PUERTO_HTTP_INTERCEPT> intercept

# Intercepción HTTPS transparente con certificados dinámicos
https_port <PUERTO_HTTPS> intercept ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=/etc/squid/certs/<NOMBRE_CA>.pem

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
visible_hostname <HOSTNAME>
```

(Nota: Las reglas `Safe_ports`, definición de redes, reglas de acceso básicas y tamaño de objeto se derivan de la configuración proporcionada. Las directivas de `intercept` y `ssl_bump` han sido agregadas para cumplir con el modo transparente requerido).

## Fase 5: Reglas de Firewall (Iptables)

Para que el modo transparente funcione, debes redirigir el tráfico web de los clientes a los puertos de intercepción de Squid.

Aplica las siguientes reglas NAT:
```bash
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port <PUERTO_HTTP>
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port <PUERTO_HTTPS>
```

## Gestión, Verificación y Troubleshooting

**1. Verificación y Arranque de Servicios:** Siempre valida la sintaxis después de realizar cambios:
```bash
squid -k parse
```

Si no hay errores fatales, inicializa los directorios de caché y reinicia el servicio:
```bash
squid -z
systemctl restart squid
systemctl enable squid
```

_Otros comandos útiles:_ `systemctl status squid`, `systemctl stop squid`.

**2. Monitoreo de Logs:** Supervisa el tráfico y los errores en tiempo real:
```bash
tail -f /var/log/squid/access.log /var/log/squid/cache.log
```

**3. Interpretación de Códigos (access.log):**

- `TCP_MISS/200`: La petición no estaba en caché; se descargó correctamente de internet y se envió al cliente.

- `TCP_DENIED/403`: El proxy bloqueó la conexión (revisa tus reglas `http_access` o `acl`).


**4. Corrupción de la Base de Datos SSL (`ssl_db`):** Si los clientes experimentan errores de certificado de manera repentina y los logs muestran fallos en `security_file_certgen`, limpia la base de datos:
```bash
systemctl stop squid
rm -rf /var/lib/squid/ssl_db/*
/usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
chown -R proxy:proxy /var/lib/squid/ssl_db
systemctl start squid
```

## Funciones Avanzadas y Próximos Pasos

Una vez estabilizada la plantilla base, puedes extender las capacidades de tu proxy implementando:

- **Filtrado de Contenido Profundo:** Integración de SquidGuard o ufdbGuard para bloquear dominios categorizados (malware, redes sociales, contenido adulto).

- **Listas de Control de Acceso (ACLs) Granulares:** Restricción de navegación atada a direcciones MAC específicas en lugar de IPs.

- **Control de Ancho de Banda (Delay Pools):** Limitación de velocidades de descarga generales o para extensiones de archivo específicas (`.mp4`, `.iso`).

- **Políticas Basadas en Horarios:** Bloqueo de acceso a ciertos dominios o servicios fuera de horas laborales.