# Automatización de Infraestructura y Servicios Linux

Repositorio de scripts en Bash diseñados para la automatización, despliegue y configuración segura de servicios de infraestructura de red y respaldos en entornos Linux.

Este proyecto demuestra la implementación práctica de servicios core de TI, priorizando la estandarización y las buenas prácticas de administración de sistemas.

## Tecnologías y Servicios Implementados

- **SO Base:** Debian / Ubuntu / Linux Mint
- **Respaldos:** Bacula (Director, Storage, File Daemon), NFS, Clonezilla
- **Redes y DNS:** Kea DHCP, BIND9 (DDNS)
- **Seguridad y Web:** OpenSSL (CA Local), Nginx, ProFTPD, UFW
- **Proxy e Inspección:** Squid Proxy (Transparente / SSL Bumping)
- **Correo:** Postfix / Dovecot

## Catálogo de Scripts

| Script | Descripción | Estado |
| :--- | :--- | :--- |
| `bacula_server_setup.sh` | Despliega y configura Bacula Server (Director, Storage) con base de datos MariaDB y Webmin. | 🟡 En revisión |
| `bacula_cliente_setup.sh` | Instala Bacula File Daemon y genera los archivos de configuración en el nodo cliente. | 🟡 En revisión |
| `ddns-kea-bind.sh` | Integra Kea DHCP con BIND9 para actualizaciones dinámicas de DNS (DDNS). | 🟡 En revisión |
| `setup_ca.sh` | Crea una Autoridad Certificadora (CA) local para emitir certificados TLS/SSL. | 🟡 En revisión |
| `setup_nginx_proftpd_secure.sh`| Despliega un servidor web y un servidor FTP securizados con certificados locales. | 🟡 En revisión |
| `nfs_clonezilla.sh` | Configura un recurso compartido NFS optimizado para almacenar imágenes de Clonezilla. | 🟡 En revisión |
| `instalar_correo.sh` | Automatiza el despliegue del servidor de correo interno. | 🟡 En revisión |
| `squid_install.sh` | Configura un proxy transparente con intercepción HTTPS (SSL Bumping) y reglas de iptables. | 🟢 Completado |

## Requisitos Previos

1. Sistema operativo basado en Debian/Ubuntu.
2. Permisos de superusuario (`root` o vía `sudo`).
3. Conectividad de red configurada (IP estática recomendada para los servidores).

## Uso y Ejecución

Por motivos de seguridad, los scripts interactivos ocultan el ingreso de contraseñas. Para ejecutar cualquier archivo de automatización, otorga permisos de ejecución y córrelo con privilegios elevados:

```bash
chmod +x nombre_del_script.sh
sudo ./nombre_del_script.sh
Notas de Seguridad
Ninguna contraseña real de infraestructura, bases de datos o credenciales de Bacula se expone en texto plano en este repositorio.

Las variables sensibles son solicitadas en tiempo de ejecución a través de la terminal de forma silenciosa.

Se recomienda ejecutar estos despliegues inicialmente en entornos virtualizados o laboratorios controlados antes de pasar a producción.

Autor: Daryl