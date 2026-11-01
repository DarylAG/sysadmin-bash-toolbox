# 1. Convenciones y Variables

Antes de iniciar el despliegue, asegúrate de reemplazar los siguientes marcadores de posición en los comandos y archivos de configuración con los valores reales de tu entorno:

- `<DOMINIO_PRINCIPAL>`: El nombre de dominio principal para el correo (ej. `dominio.com`).

- `<HOSTNAME_CORREO>`: El nombre corto del servidor (ej. `mail` o `beta`).

- `<FQDN_CORREO>`: El nombre de dominio completamente calificado del servidor (ej. `mail.dominio.com`).

- `<IP_SERVIDOR>`: Dirección IP estática asignada a este servidor (ej. `192.168.100.2`).

- `<IP_GATEWAY>`: Dirección IP de la puerta de enlace de la red (ej. `192.168.100.254`).

- `<IP_DNS>`: Servidor de resolución de nombres (ej. `192.168.100.1`).

- `<RED_LOCAL>`: El segmento de red permitido para el retransmisor (relay) local (ej. `192.168.100.0/24`).

- `<USUARIO_CORREO>`: Nombre del usuario del sistema que tendrá un buzón de correo (ej. `juanperez`).

- `<CA_USER>@<CA_HOST>`: Usuario y servidor donde reside la Autoridad Certificadora para copiar los certificados.


# 2. Preparación del Sistema y Red

**Acción:** Configurar el nombre de host corto del servidor.

Bash

```bash
hostnamectl set-hostname <HOSTNAME_CORREO>
```

**Acción:** Ajustar la resolución local para incluir el FQDN apuntando a la interfaz de loopback.
```bash
nano /etc/hosts
	127.0.0.1       localhost
	127.0.1.1       <FQDN_CORREO>    <HOSTNAME_CORREO>
```

**Acción:** Configurar los servidores DNS locales.
```bash
nano /etc/resolv.conf 
	search <DOMINIO_PRINCIPAL> 
	nameserver <IP_DNS> 
```

**Acción:** Asignar la dirección IP estática en la interfaz de red primaria. _(Nota: Ajusta `enp0s3` según el nombre real de tu interfaz)._
```bash
nano /etc/network/interfaces
	# The primary network interface
	allow-hotplug enp0s3
	iface enp0s3 inet static
	    address <IP_SERVIDOR>
	    netmask 255.255.255.0
	    gateway <IP_GATEWAY>
```

**Acción:** Actualizar los repositorios y paquetes del sistema.
```bash
apt update && apt upgrade -y
```

# 3. Gestión de Certificados SSL/TLS

**Acción:** Importar los certificados TLS/SSL generados desde el servidor CA y asignar los permisos restrictivos necesarios.

*Opción A: Copia desde rutas locales*
```bash
cp /ruta/local/<HOSTNAME_CORREO>.crt /etc/ssl/certs/<HOSTNAME_CORREO>.crt
cp /ruta/local/<HOSTNAME_CORREO>.key /etc/ssl/private/<HOSTNAME_CORREO>.key
cp /ruta/local/ca-root.crt /etc/ssl/certs/ca-root.crt
```
*Opción B: Transferencia remota desde el servidor CA*

```Bash
scp <CA_USER>@<CA_HOST>:/ruta/ca/certs/<HOSTNAME_CORREO>.crt /etc/ssl/certs/<HOSTNAME_CORREO>.crt
scp <CA_USER>@<CA_HOST>:/ruta/ca/private/<HOSTNAME_CORREO>.key /etc/ssl/private/<HOSTNAME_CORREO>.key
scp <CA_USER>@<CA_HOST>:/ruta/ca/certs/ca-root.crt /etc/ssl/certs/ca-root.crt
```

Asegurar la llave privada
```bash
chmod 600 /etc/ssl/private/<HOSTNAME_CORREO>.key
chown root:root /etc/ssl/private/<HOSTNAME_CORREO>.key
```

# 4. Instalación y Configuración de Postfix (MTA)

**Acción:** Instalar el agente de transferencia de correo y herramientas básicas.
```bash
apt update && apt install -y postfix mailutils
```

**Acción:** Respaldar y optimizar la configuración principal (`main.cf`).
```bash
cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
nano /etc/postfix/main.cf
```

```bash
# Nivel de compatibilidad y dominios
compatibility_level = 3.9
mydomain = <DOMINIO_PRINCIPAL>
myorigin = $mydomain
myhostname = <FQDN_CORREO>
mydestination = $myhostname, <DOMINIO_PRINCIPAL>, localhost.$mydomain, localhost

# Red e Interfaces
inet_protocols = ipv4
inet_interfaces = all
mynetworks_style = host
mynetworks = 127.0.0.0/8 <RED_LOCAL>

# Buzones de correo (Maildir)
mailbox_size_limit = 0
home_mailbox = Maildir/
mailbox_command = 
recipient_delimiter = +
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

# Configuración TLS
smtpd_tls_key_file = /etc/ssl/private/<HOSTNAME_CORREO>.key
smtpd_tls_cert_file = /etc/ssl/certs/<HOSTNAME_CORREO>.crt
smtp_tls_CAfile = /etc/ssl/certs/ca-root.crt
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache
smtpd_tls_auth_only = yes
smtpd_tls_loglevel = 1

# Autenticación SASL integrada con Dovecot
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = $myhostname

# Restricciones de envío
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
```

**Acción:** Respaldar y configurar el proceso maestro (`master.cf`) para habilitar el puerto de envío seguro SMTP Submission (587).
```bash
cp /etc/postfix/master.cf /etc/postfix/master.cf.bak
nano /etc/postfix/master.cf
```
```bash
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
        -o syslog_name=${multi_instance_name?{$multi_instance_name}:{postfix}}/$service_name
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

```

# 5. Instalación y Configuración de Dovecot (IMAP/POP3)

**Acción:** Instalar los servicios de Dovecot.
```bash
apt install -y dovecot-imapd dovecot-pop3d
```

**Acción:** Respaldar y configurar los parámetros SSL (`10-ssl.conf`) para forzar conexiones seguras.
```bash
cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf.bak
nano /etc/dovecot/conf.d/10-ssl.conf
```
```bash
# Requerir SSL y definir rutas de certificados
ssl = required
ssl_server_cert_file = /etc/ssl/certs/<HOSTNAME_CORREO>.crt
ssl_server_key_file = /etc/ssl/private/<HOSTNAME_CORREO>.key
ssl_server_ca_file = /etc/ssl/certs/ca-root.crt

# Protocolo mínimo aceptado
ssl_min_protocol = TLSv1.2
```

**Acción:** Respaldar y configurar los mecanismos de autenticación (`10-auth.conf`).
```bash
cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.bak
nano /etc/dovecot/conf.d/10-auth.conf
```
```bash
!include auth-system.conf.ext
```

**Acción:** Respaldar y configurar los sockets de autenticación para Postfix (`10-master.conf`).
```bash
cp /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.bak
nano /etc/dovecot/conf.d/10-master.conf
```
```bash
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

```

## 6. Creación de Usuarios y Estructura Maildir

**Acción:** Crear usuarios del sistema sin acceso a shell y preparar su estructura de buzón Maildir.
Crear usuario
```bash
useradd -m -s /sbin/nologin -c "Usuario de Correo" <USUARIO_CORREO>
passwd <USUARIO_CORREO>
```
Crear estructura Maildir y asignar permisos
```bash
mkdir -p /home/<USUARIO_CORREO>/Maildir/{new,cur,tmp}
chown -R <USUARIO_CORREO>:<USUARIO_CORREO> /home/<USUARIO_CORREO>/Maildir/
chmod -R 700 /home/<USUARIO_CORREO>/Maildir/
```

## 7. Gestión, Verificación y Troubleshooting

**Control de Servicios:**
```bash
systemctl restart postfix dovecot
systemctl enable postfix dovecot
systemctl status postfix dovecot
```

**Verificación de Configuración Activa:** Para validar que no hay errores de sintaxis y ver los parámetros cargados en memoria:
Verificar Postfix
```bash
postconf -n
```
Verificar Dovecot
```bash
doveconf -n
```

**Prueba de Conexión TLS/SSL:** Comprueba que el certificado se esté entregando correctamente en el puerto IMAPS (993).
```bash
openssl s_client -connect <FQDN_CORREO>:993 -CAfile /etc/ssl/certs/ca-root.crt
```

**Diagnóstico de Correo (Troubleshooting):**

- **Ver la cola de correos:** `mailq` o `postqueue -p`

- **Forzar el envío de la cola:** `postqueue -f`

- **Borrar todos los correos encolados:** `postsuper -d ALL`

- **Monitoreo en tiempo real de transacciones (Logs):**
```bash
tail -f /var/log/mail.log
```

Alternativa moderna si el sistema usa systemd-journald:
```bash
journalctl -u postfix -u dovecot -f
```

- **Fallo de Autenticación (SASL):** Si los clientes no pueden enviar correo (Error 535), verifica que el socket en `/var/spool/postfix/private/auth` se creó correctamente y tiene los permisos adecuados definidos en `10-master.conf`.

- **Rechazo de Relay (Relay Access Denied):** Verifica que la IP pública o local del cliente esté contemplada en la directiva `mynetworks` dentro de `main.cf`, o que el cliente esté enviando correo autenticado correctamente por el puerto 587.


## 8. Funciones Avanzadas y Próximos Pasos

Una vez validada la funcionalidad base, se recomienda implementar las siguientes mejoras para asegurar un entorno de producción óptimo:

- **Registros DNS de Seguridad:** Implementación de **SPF** (Sender Policy Framework), **DKIM** (DomainKeys Identified Mail) y **DMARC** (Domain-based Message Authentication, Reporting, and Conformance) para evitar que los correos sean marcados como SPAM.

- **Integración Webmail:** Despliegue de un cliente web como **Roundcube** acoplado a un servidor web (Nginx/Apache) y PHP-FPM.

- **Usuarios Virtuales (Base de Datos):** Migración de cuentas de sistema (`/etc/passwd`) a usuarios virtuales gestionados mediante MariaDB/MySQL o PostgreSQL, permitiendo hospedar múltiples dominios virtuales (Virtual Domains).

- **Antispam y Antivirus:** Integración de **SpamAssassin** y **ClamAV** a través de Amavis o Rspamd.