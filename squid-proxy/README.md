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
```
hostnamectl set-hostname <HOSTNAME>
```

Actualizar repositorios e instalar Squid y utilidades de firewall:
```
apt update && apt upgrade -y
apt install squid iptables squid-openssl -y
```

## Fase 2: Gestión de Certificados para SSL Bumping

Para que Squid intercepte tráfico cifrado (HTTPS), debe actuar como una Autoridad Certificadora (CA) para generar certificados dinámicos. Es obligatorio combinar el certificado público y la clave privada sin contraseña en un único archivo `.pem`.

MD

1. Posiciónate en el directorio de certificados de Squid:
```
mkdir -p /etc/squid/certs
cd /etc/squid/certs/
```

2. Genera el archivo `.pem` concatenando el certificado (`.crt`) y la llave privada (`.key`):
```
cat <NOMBRE_CA>.crt <NOMBRE_CA>.key > <NOMBRE_CA>.pem
```

3. Ajusta los permisos de seguridad (crítico para Squid):
```
chown -R proxy:proxy /etc/squid/certs
chmod 755 /etc/squid/certs
chmod 600 /etc/squid/certs/<NOMBRE_CA>.pem
```

## Fase 3: Inicialización de la Base de Datos SSL

Squid requiere un directorio para almacenar los certificados generados dinámicamente para cada sitio web.

1. Crea la estructura y asigna permisos:
```
mkdir -p /var/lib/squid
chown -R proxy:proxy /var/lib/squid
```

2. Inicializa la base de datos `ssl_db` (tamaño ajustado a 4MB):
```
/usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
chown -R proxy:proxy /var/lib/squid/ssl_db
```

## Fase 4: Configuración de Squid (`squid.conf`)

Respalda el archivo de configuración original:
```
mkdir -p /etc/squid/backup
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
mv /etc/squid/*.bak /etc/squid/backup/
```

Edita el archivo de configuración limpio:
```
nano /etc/squid/squid.conf
```
[[squid.conf]]

(Nota: Las reglas `Safe_ports`, definición de redes, reglas de acceso básicas y tamaño de objeto se derivan de la configuración proporcionada. Las directivas de `intercept` y `ssl_bump` han sido agregadas para cumplir con el modo transparente requerido).

## Fase 5: Reglas de Firewall (Iptables)

Para que el modo transparente funcione, debes redirigir el tráfico web de los clientes a los puertos de intercepción de Squid.

Aplica las siguientes reglas NAT:
```
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port <PUERTO_HTTP>
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port <PUERTO_HTTPS>
```

## Gestión, Verificación y Troubleshooting

**1. Verificación y Arranque de Servicios:** Siempre valida la sintaxis después de realizar cambios:
```
squid -k parse
```

Si no hay errores fatales, inicializa los directorios de caché y reinicia el servicio:
```
squid -z
systemctl restart squid
systemctl enable squid
```

_Otros comandos útiles:_ `systemctl status squid`, `systemctl stop squid`.

**2. Monitoreo de Logs:** Supervisa el tráfico y los errores en tiempo real:
```
tail -f /var/log/squid/access.log /var/log/squid/cache.log
```

**3. Interpretación de Códigos (access.log):**

- `TCP_MISS/200`: La petición no estaba en caché; se descargó correctamente de internet y se envió al cliente.

- `TCP_DENIED/403`: El proxy bloqueó la conexión (revisa tus reglas `http_access` o `acl`).


**4. Corrupción de la Base de Datos SSL (`ssl_db`):** Si los clientes experimentan errores de certificado de manera repentina y los logs muestran fallos en `security_file_certgen`, limpia la base de datos:
```
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