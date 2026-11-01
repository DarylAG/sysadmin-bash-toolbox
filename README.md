# SysAdmin Bash Toolbox - Automatización de Infraestructura Linux

Repositorio de Infraestructura como Código (IaC) en Bash diseñado para el aprovisionamiento, despliegue y hardening seguro de servicios core de red, proxy, correo y respaldos en entornos Linux (Debian/Ubuntu).

Este proyecto prioriza la **seguridad perimetral, el cifrado de punto a punto y la mitigación de vectores de ataque comunes** (Open Relay, Spoofing DNS, Man-in-the-Middle, filtración de credenciales), implementando configuraciones robustas y estandarizadas listas para producción.

---

## Pilares de Seguridad en Servicios de Red

- **Cifrado Criptográfico Obligatorio (TLS/SSL):** Desactivación de protocolos obsoletos y forzado de algoritmos modernos (TLS 1.2 / TLS 1.3 con ciphers `HIGH:!aNULL:!MD5`) en servidores Web (Nginx), FTP (ProFTPD), SMTP (Postfix) e IMAP/POP3 (Dovecot). 

- **Control de Acceso y Aislamiento Perimetral:** 
	- Enjaulamiento estricto (`Chroot`) en servidores de archivos para prevenir escalada de directorios. 
	- Asignación de shells no interactivas (`/usr/sbin/nologin`) para usuarios dedicados a servicios de red. 
	- Definición explícita de subredes confiables (`ACLs`) en BIND9 y Squid. 

- **Autenticación Fuerte e Integridad DDNS:** Actualizaciones dinámicas de DNS (Kea DHCP -> BIND9) firmadas mediante llaves simétricas TSIG (`HMAC-SHA256`) y controladas por directivas `update-policy`. 

- **Protección de Correo y Web:** 
    - Configuración estricta Anti-Open Relay y autenticación SASL sobre puerto seguro Submission (587). 
	
    - Inspección SSL Bumping y filtrado perimetral controlado en Proxy Squid. 
	
	- Cabeceras de seguridad HTTP (`X-Frame-Options`, `X-Content-Type-Options`) contra ataques de red comunes.

---

## Arquitectura del Repositorio

```text
sysadmin-bash-toolbox/
├── README.md
└── scripts/
    ├── bacula-server/
    │   ├── deploy-bacula-server.sh
    │   ├── deploy-bacula-client.sh
    │   └── README.md
    ├── ddns-bind9-kea/
    │   ├── deploy-bind9-kea-ddns.sh
    │   └── README.md
    ├── nginx-proftpd/
    │   ├── deploy-nginx-proftpd.sh
    │   └── README.md
    ├── clonezilla-nfs/
    │   ├── deploy-nfs-clonezilla.sh
    │   └── README.md
    ├── squid-proxy/
    │   ├── deploy-squid-proxy.sh
    │   └── README.md
    ├── postfix-dovecot/
    │   ├── deploy-postfix-dovecot.sh
    │   └── README.md
    └── ca-infrastructure/
        ├── deploy-pki-ca.sh
        └── README.md
```

---
## Catálogo de Laboratorios y Estado de Auditoría

| **Laboratorio**       | **Script de Despliegue**    | **Descripción Técnica**                                                                              | **Estado**      |
| --------------------- | --------------------------- | ---------------------------------------------------------------------------------------------------- | --------------- |
| **`bacula-server`**   | `deploy-bacula-server.sh`   | Servidor de respaldos Bacula (Director, Storage Daemon) con MariaDB y Webmin.                        | 🟡 En revisión  |
| **`bacula-server`**   | `deploy-bacula-client.sh`   | Agente cliente de respaldos Bacula (File Daemon) y llaves de autenticación.                          | 🟡 En revisión  |
| **`ddns-bind9-kea`**  | `deploy-bind9-kea-ddns.sh`  | Integración de Kea DHCP con BIND9 mediante llaves TSIG (HMAC-SHA256) para DDNS.                      | 🟢 Completado   |
| **`nginx-proftpd`**   | `deploy-nginx-proftpd.sh`   | Servidor Web Nginx (HTTPS forzado) y FTP Seguro (ProFTPD con FTPS explícito y Chroot).               | 🟢 Completado   |
| **`clonezilla-nfs`**     | `deploy-nfs-clonezilla.sh`     | Almacenamiento en red NFS (Preparado para integración con DRBL / Clonezilla).                        | ⏳ En desarrollo |
| **`squid-proxy`**     | `deploy-squid-proxy.sh`     | Proxy transparente Squid con inspección SSL (SSL Bumping), base de datos `ssl_db` y reglas Iptables. | 🟢 Completado   |
| **`postfix-dovecot`** | `deploy-postfix-dovecot.sh` | Servidor de correo interno con Postfix (MTA), Dovecot (IMAP/POP3), SASL y Submission cifrado (587).  | 🟢 Completado   |
| **`pki-ca`**          | `deploy-pki-ca.sh`          | Infraestructura de clave pública (PKI) y Autoridad Certificadora (CA) local con OpenSSL.             | 🟢 Completado |

---
## Estándares de Diseño y Seguridad

- **Manejo Estricto de Errores:** Todos los scripts incluyen la directiva `set -euo pipefail` para prevenir ejecuciones parciales o inconsistentes ante fallos de comandos.

- **Resiliencia de Configuración:** Implementación de la función interna `backup_file()` para resguardar archivos `.bak` con marcas de tiempo antes de inyectar cambios.

- **Seguridad Criptográfica:** Permisos restrictivos (`chmod 600`) aplicados sistemáticamente sobre llaves privadas TLS, secretos TSIG y credenciales.

- **Enjaulamiento y Aislamiento:** Uso de shells no interactivas (`/usr/sbin/nologin`) para usuarios de servicios y políticas de `Chroot` en servidores de archivos.

- **Higiene de Datos:** Captura silenciosa de credenciales en tiempo real (`read -s`); sin almacenamiento de llaves ni contraseñas en texto plano dentro del código.

---
## Uso y Ejecución

1. Clona el repositorio en tu servidor de laboratorio:
```Bash
git clone https://github.com/DarylAG/sysadmin-bash-toolbox.git
cd sysadmin-bash-toolbox
```

2. Navega al laboratorio deseado y otorga permisos de ejecución:
```bash
cd scripts/lab06-squid-proxy/
chmod +x deploy-squid-proxy.sh
sudo ./deploy-squid-proxy.sh
```

3. Consulta la guía de operación paso a paso en el archivo `README.md` dentro de cada directorio de laboratorio para pruebas manuales o troubleshooting.

**Autor:** Daril Arias
