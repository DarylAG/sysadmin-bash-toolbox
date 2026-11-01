# 1. Convenciones y Variables

Antes de ejecutar los comandos en esta guía, asegúrese de reemplazar los siguientes marcadores de posición con los valores correspondientes a su entorno:

- `<HOSTNAME>`: Nombre del servidor (ej. `gamma`).

- `<DOMINIO_WEB>`: Nombre de dominio principal (ej. `xeon.cr`).

- `<FQDN>`: Nombre de dominio completamente calificado (ej. `gamma.xeon.cr`).

- `<IP_SERVIDOR>`: Dirección IP estática del servidor (ej. `192.168.106.3`).

- `<MASCARA_RED>`: Máscara de subred (ej. `255.255.255.0`).

- `<PUERTA_ENLACE>`: IP del Gateway de la red (ej. `192.168.106.254`).

- `<IP_DNS>`: Dirección IP del servidor de nombres/DNS (ej. `192.168.106.1`).

- `<INTERFAZ_RED>`: Interfaz de red principal (ej. `enp0s3`).

- `<RUTA_RAIZ_WEB>`: Directorio principal de los archivos del sitio (ej. `/var/www/xeon.cr`).

- `<USUARIO_FTP>`: Usuario encargado de administrar los archivos web vía FTP (ej. `webadmin`).


# 2. Estructura de Paso a Paso: Configuración Base del Sistema

**Acción:** Configurar el nombre del host. **Comando:**
```bash
hostnamectl set-hostname <HOSTNAME>
```

**Acción:** Mapear el nombre del host localmente. **Comando:**
```bash
nano /etc/hosts
	127.0.0.1       localhost
	127.0.1.1       <FQDN>   <HOSTNAME>
```

**Acción:** Configurar la IP estática. **Comando:**
```bash
nano /etc/network/interfaces
	# Interfaz de red principal
	allow-hotplug <INTERFAZ_RED>
	iface <INTERFAZ_RED> inet static
	    address <IP_SERVIDOR>
	    netmask <MASCARA_RED>
	    gateway <PUERTA_ENLACE>
```

**Acción:** Definir la resolución DNS. **Comando:*
```bash
nano /etc/resolv.conf
	nameserver <IP_DNS>
	search <DOMINIO_WEB>
```

**Acción:** Actualizar repositorios e instalar paquetes base. **Comando:**
```bash
apt update && apt upgrade -y
```

## 3. Despliegue y Configuración de Nginx

**Acción:** Instalar Nginx y crear el directorio raíz para el sitio web. **Comandos:**
```bash
apt install nginx -y
mkdir -p <RUTA_RAIZ_WEB>/html
```

**Acción:** Transferir, renombrar y asegurar los certificados SSL/TLS estandarizados.
**Comandos:**
```bash
# Copiar y asegurar llave privada
cp /ruta/origen/<LLAVE_SSL>.key /etc/ssl/private/<DOMINIO_WEB>.key
chown root:root /etc/ssl/private/<DOMINIO_WEB>.key
chmod 600 /etc/ssl/private/<DOMINIO_WEB>.key

# Copiar certificados públicos
cp /ruta/origen/<CERTIFICADO_CA>.crt /etc/ssl/certs/ca_<DOMINIO_WEB>.crt
chown root:root /etc/ssl/certs/ca_<DOMINIO_WEB>.crt
chmod 644 /etc/ssl/certs/ca_<DOMINIO_WEB>.crt

cp /ruta/origen/<CERTIFICADO_SSL>.crt /etc/ssl/certs/<DOMINIO_WEB>.crt
chown root:root /etc/ssl/certs/<DOMINIO_WEB>.crt
chmod 644 /etc/ssl/certs/<DOMINIO_WEB>.crt
```

**Acción:** Crear un sitio index.html inicial de prueba.Comando:

```Bash
cat <<EOF> <RUTA_RAIZ_WEB>/html/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Bienvenido a <DOMINIO_WEB></title>
</head>
<body>
    <h1>Servidor <DOMINIO_WEB> en línea</h1>
</body>
</html>
EOF
```

**Acción:** Crear el archivo de configuración del sitio web (Virtual Host) forzando HTTPS.
**Comando:**
```bash
nano /etc/nginx/sites-available/<DOMINIO_WEB>
```
```bash
# Redirección obligatoria de HTTP a HTTPS
server {
    listen 80;
    server_name <DOMINIO_WEB> www.<DOMINIO_WEB>;
    return 301 https://$host$request_uri;
}

# Bloque principal para conexiones HTTPS
server {
    listen 443 ssl;
    server_name <DOMINIO_WEB> www.<DOMINIO_WEB>;

    root <RUTA_RAIZ_WEB>/html;
    index index.html index.htm;

    ssl_certificate /etc/ssl/certs/<DOMINIO_WEB>.crt;
    ssl_certificate_key /etc/ssl/private/<DOMINIO_WEB>.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files $uri $uri/ =404;
    }

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
}
```

**Acción:** Habilitar el sitio mediante un enlace simbólico. 
**Comando:**
```bash
ln -s /etc/nginx/sites-available/<DOMINIO_WEB> /etc/nginx/sites-enabled/
```

# 4. Gestión de Usuarios y Permisos para FTP/Web

**Acción:** Crear un usuario de sistema sin acceso a shell interactiva, pero con permisos para administrar el directorio web. 
**Comandos:**
```bash
useradd -m -d <RUTA_RAIZ_WEB> -s /usr/sbin/nologin <USUARIO_FTP>
passwd <USUARIO_FTP>
chown -R <USUARIO_FTP>:www-data <RUTA_RAIZ_WEB>
chmod -R 775 <RUTA_RAIZ_WEB>
```

# 5. Despliegue y Configuración de ProFTPD

**Acción:** Instalar el servidor ProFTPD y su módulo criptográfico para soporte TLS.
**Comando:**
```bash
apt install proftpd-basic proftpd-mod-crypto -y
```

**Acción:** Configurar los parámetros principales del servidor FTP, enjaulando al usuario y restringiendo accesos.
**Comando:**
```bash
cp /etc/proftpd/proftpd.conf /etc/proftpd/proftpd.conf.bak
nano /etc/proftpd/proftpd.conf
```

```bash
# Carga de módulos dinámicos
Include /etc/proftpd/modules.conf

# Soporte IPv6 activado
UseIPv6 on

<IfModule mod_ident.c>
    # Desactivar peticiones de identificación para evitar demoras en la conexión
    IdentLookups off
</IfModule>

# Nombre del servidor que verán los clientes al conectarse
ServerName "<HOSTNAME> FTP Server"

# Configuración del demonio como servidor independiente principal
ServerType standalone
DefaultServer on

# Tiempos máximos de espera (en segundos)
TimeoutNoTransfer 600
TimeoutStalled 600
TimeoutIdle 1200

# Opciones de presentación y filtros de seguridad
DeferWelcome off
ShowSymlinks on
DisplayLogin welcome.msg
DisplayChdir .message true
ListOptions "-l"
DenyFilter \*.*/

# Enjaular a todos los usuarios dentro de sus directorios base por seguridad (Chroot)
DefaultRoot ~

# Permitir el acceso a usuarios que no poseen una shell interactiva (ej. /usr/sbin/nologin)
RequireValidShell off

# Puerto estándar de conexión FTP
Port 21

# Rango de puertos pasivos para conexiones a través de Firewalls o NAT (Descomentar si aplica)
# PassivePorts <PUERTOS_PASIVOS_INICIO> <PUERTOS_PASIVOS_FIN>

# Límite de conexiones simultáneas para mitigar ataques DoS
MaxInstances 30

# Usuario y grupo bajo los que opera el servicio ProFTPD
User proftpd
Group nogroup

# Máscara de permisos por defecto para los archivos/directorios nuevos y sobreescritura
Umask 022 022
AllowOverwrite on

# Rutas de los logs de transferencias y eventos generales del servicio
TransferLog /var/log/proftpd/xferlog
SystemLog /var/log/proftpd/proftpd.log

<IfModule mod_delay.c>
    # Mitigación de ataques de temporización (Timing Attacks)
    DelayEngine on
</IfModule>

# Inclusión del archivo de configuración para conexiones seguras (FTPS)
Include /etc/proftpd/tls.conf

# Bloque de seguridad: Restringir el inicio de sesión FTP ÚNICAMENTE a nuestro usuario web
<Limit LOGIN>
  AllowUser <USUARIO_FTP>
  DenyAll
</Limit>

# Directorio para otras configuraciones personalizadas
Include /etc/proftpd/conf.d/
```

**Acción:** Configurar el módulo TLS de ProFTPD para habilitar FTPS explícito y forzar conexiones cifradas.
**Comando:**
```bash
nano /etc/proftpd/tls.conf
```
```bash
<IfModule mod_tls.c>
    TLSEngine on
    TLSLog /var/log/proftpd/tls.log
    TLSProtocol TLSv1.2 TLSv1.3

    # Rutas estandarizadas consumidas desde Nginx
    TLSRSACertificateFile /etc/ssl/certs/<DOMINIO_WEB>.crt
    TLSRSACertificateKeyFile /etc/ssl/private/<DOMINIO_WEB>.key
    TLSCACertificateFile /etc/ssl/certs/ca_<DOMINIO_WEB>.crt

    TLSVerifyClient off
    TLSRequired on
</IfModule>
```

**Acción:** Habilitar configuraciones necesarias de módulos.
**Comando:**
```bash
nano /etc/proftpd/modules.conf
```
_(Nota: Verifique que la línea `LoadModule mod_tls.c` esté sin comentar)._

## 6. Sección de Gestión, Verificación y Troubleshooting
Para asegurar que ambos servicios funcionen correctamente después de aplicar las configuraciones, utilice los siguientes comandos:

**Verificación de Sintaxis (Obligatorio antes de reiniciar):**

- **Nginx:** `nginx -t`

- **ProFTPD:** `proftpd -t`

**Comandos de Control de Servicios:**

- **Nginx:** `systemctl start | stop | restart | reload | status nginx`

- **ProFTPD:** `systemctl start | stop | restart | reload | status proftpd`


**Troubleshooting y Logs:**

- **Revisión en tiempo real (Systemd):**
    
    - `journalctl -u nginx`
    
    - `journalctl -u proftpd`
    
- **Rutas de Logs:**
    
    - Errores web: `tail -f /var/log/nginx/error.log` (o el log específico definido como `/var/log/nginx/<DOMINIO_WEB>.error.log`).
    
    - Eventos FTP: `tail -f /var/log/proftpd/proftpd.log`.
    
    - Eventos TLS FTP: `tail -f /var/log/proftpd/tls.log`.
    
- **Errores Comunes:**
    
    - **Nginx - Error 403 Forbidden:** Suele ocurrir si los permisos del directorio `<RUTA_RAIZ_WEB>` no son correctos o falta el archivo `index.html`. Asegúrese de que el usuario `www-data` pueda leer los archivos.
    
    - **ProFTPD - Fallo en modo pasivo:** Ocurre comúnmente detrás de NAT. Asegúrese de que el rango de `PassivePorts` (ej. 49152-65534) esté abierto en el firewall (UFW/iptables).
    
    - **ProFTPD - Fallo de conexión TLS:** Asegúrese de que el cliente FTP (como FileZilla) esté configurado para requerir "FTP explícito sobre TLS".
    

## 7. Funciones Avanzadas y Próximos Pasos

Con la configuración aplicada, el entorno ya cuenta con una base sólida de seguridad perimetral, habiendo implementado exitosamente el cifrado HTTPS forzado mediante Nginx y el soporte para sesiones seguras obligatorias en ProFTPD. Para continuar evolucionando esta arquitectura hacia estándares de alta disponibilidad y producción, considere:

- **Seguridad Activa (Fail2Ban):** Implementar políticas de Fail2Ban para monitorear activamente los logs de acceso de Nginx y ProFTPD, bloqueando automáticamente a nivel de firewall (iptables/UFW) las direcciones IP que realicen múltiples intentos fallidos de autenticación o muestren patrones maliciosos.

- **Gestión y Rotación de Logs (Logrotate):** Establecer reglas estrictas de rotación, compresión y retención para los directorios `/var/log/nginx/` y `/var/log/proftpd/`, garantizando que el almacenamiento del servidor no se sature a lo largo del tiempo.

- **Automatización de Certificados SSL/TLS:** Desarrollar un flujo de trabajo (mediante scripts cron o Ansible) para la renovación y despliegue automático de los certificados de la CA interna antes de su expiración, reduciendo el margen de error humano.

- **Alta Disponibilidad y Balanceo de Carga:** Utilizar el servidor Nginx actual como proxy inverso (Reverse Proxy) y balanceador de carga (Load Balancer) para distribuir el tráfico web entrante hacia un clúster de servidores backend.

- **Telemetría y Monitoreo:** Integrar agentes de monitoreo de métricas (como Prometheus con Node Exporter, o Netdata) para visualizar en tiempo real el consumo de CPU/RAM, ancho de banda de red, y la cantidad de conexiones simultáneas tanto web como FTP.