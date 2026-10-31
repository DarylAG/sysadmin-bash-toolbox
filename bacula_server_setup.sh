#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Instalación y configuración automatizada de Bacula Server 
#            (Director, SD, FD), MariaDB y Webmin.
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

# SEGURIDAD: Abortar la ejecución ante variables no declaradas o errores ocultos 
# evita despliegues parciales que podrían dejar el sistema de respaldos inoperante.
set -euo pipefail

log_info() {
  echo -e "\n\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\n\e[31m[ERROR]\e[0m $1"
}

verificar_privilegios() {
  log_info "Verificando privilegios de administrador..."
  # SEGURIDAD: La instalación de demonios de respaldo y bases de datos requiere 
  # acceso profundo a los recursos del sistema y configuración de red.
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script requiere privilegios de administrador. Ejecútalo como root o usando sudo."
    exit 1
  fi
}

backup_file() {
  # SERVICIO: Garantiza la resiliencia de la configuración. Antes de inyectar 
  # nuevos parámetros, se preserva el estado anterior para facilitar un rollback.
  local FILE=$1
  if [ -f "$FILE" ]; then
    local BACKUP_NAME
    BACKUP_NAME="${FILE}.bak_$(date +%F)"
    cp -a "$FILE" "$BACKUP_NAME"
    echo "[Backup] Creado: $BACKUP_NAME"
  fi
}

# ==============================================================================
# 1. RECOLECCIÓN DE DATOS
# ==============================================================================
recoleccion_variables() {
  log_info "Recolección de variables dinámicas..."
  
  read -r -p "Ingrese la IP del servidor (ej: 192.168.106.1): " SERVER_IP
  
  # RELACIÓN CRUZADA: Esta contraseña será utilizada por Bacula Director para 
  # autenticarse contra el catálogo SQL en MariaDB. Debe coincidir con la 
  # solicitada durante la instalación interactiva de los paquetes.
  read -r -s -p "Ingrese la contraseña para Bacula/MySQL: " DB_PASSWORD
  echo "" 
  
  read -r -s -p "Ingrese la contraseña para bconsole: " BACULA_PASSWORD
  echo "" 
  
  read -r -s -p "Ingrese la contraseña para los clientes Bacula (FD): " BACULA_FD_PASSWORD
  echo ""

  if [ -z "$SERVER_IP" ] || [ -z "$DB_PASSWORD" ] || [ -z "$BACULA_PASSWORD" ] || [ -z "$BACULA_FD_PASSWORD" ]; then
    log_error "Error: La IP y las contraseñas son obligatorias."
    exit 1
  fi

  log_info "Generando contraseñas internas (Director, Storage, Bconsole)..."
  
  # SEGURIDAD: Se inyecta entropía criptográfica (24 caracteres) para las contraseñas 
  # de comunicación interna (RPC) entre los distintos demonios de Bacula, 
  # mitigando ataques de fuerza bruta en la red local.
  BACULA_DIR_PASSWORD=$(openssl rand -base64 24)
  BACULA_SD_PASSWORD=$(openssl rand -base64 24)
  BACULA_PASSWORD=$(openssl rand -base64 24) 

  echo "Credenciales autogeneradas de Bacula (Guárdelas en un lugar seguro):" > /root/bacula_passwords.txt
  echo "Director Daemon: $BACULA_DIR_PASSWORD" >> /root/bacula_passwords.txt
  echo "Storage Daemon: $BACULA_SD_PASSWORD" >> /root/bacula_passwords.txt
  echo "Bconsole (Consola): $BACULA_PASSWORD" >> /root/bacula_passwords.txt
  echo "Clientes Bacula (FD): $BACULA_FD_PASSWORD" >> /root/bacula_passwords.txt
  
  # SEGURIDAD: Restricción absoluta del archivo de credenciales. Al contener 
  # las llaves maestras del clúster de respaldos, solo root debe tener acceso.
  chmod 600 /root/bacula_passwords.txt
}

# ==============================================================================
# 2. INSTALACIÓN DE DEPENDENCIAS Y SERVICIOS BASE
# ==============================================================================
instalacion_dependencias() {
  log_info "Actualizando repositorios e instalando dependencias..."
  apt update && apt upgrade -y
  apt install apache2 mariadb-server mariadb-client php -y
  
  # SERVICIO: El proceso no es completamente desatendido. Las pantallas de 
  # dbconfig-common se invocarán aquí para construir y enlazar el catálogo SQL 
  # de Bacula dentro del motor de MariaDB.
  apt install bacula bacula-client bacula-common-mysql bacula-director-mysql bacula-sd bacula-server bacula-tray-monitor -y
  apt install perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions libdbd-mysql-perl wget -y

  # ==============================================================================
  # 4. INSTALACIÓN DE WEBMIN (INTERFAZ GRÁFICA)
  # ==============================================================================
  log_info "Instalando Webmin..."
  cd /tmp
  wget -q https://sourceforge.net/projects/webadmin/files/webmin/2.670/webmin_2.670_all.deb -O webmin_2.670_all.deb
  
  # SERVICIO: Webmin actúa como panel de administración integral (incluyendo módulos 
  # visuales de Bacula) para facilitar la auditoría y gestión de respaldos.
  dpkg -i webmin_2.670_all.deb || apt-get install -f -y
}

# ==============================================================================
# 5. PREPARACIÓN DEL DIRECTORIO DE RESPALDOS
# ==============================================================================
preparacion_directorio() {
  log_info "Preparando directorio de respaldos" 
  # SERVICIO: Punto de montaje o ruta física local donde el Storage Daemon (SD) 
  # creará y gestionará los volúmenes lógicos (archivos contenedores) de los backups.
  mkdir -p /copias
  chmod 777 /copias
}

# ==============================================================================
# 6. CONFIGURACIÓN DE BACULA (DIRECTOR)
# ==============================================================================
configurar_bacula_dir () {
  log_info "Configurando Bacula Director..."
  backup_file "/etc/bacula/bacula-dir.conf"
  
  cat << EOF > /etc/bacula/bacula-dir.conf
# SERVICIO: El Director es el cerebro del clúster. Orquesta las tareas de respaldo, 
# se comunica con los clientes (FD), envía los datos al almacenamiento (SD) 
# y registra los metadatos en el catálogo (MariaDB).
Director {
  Name = bacula-dir
  DIRport = 9101
  QueryFile = "/etc/bacula/scripts/query.sql"
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 20
  # SEGURIDAD: Llave criptográfica requerida por bconsole u otros directores 
  # para enviar instrucciones a este Director.
  Password = "${BACULA_DIR_PASSWORD}"
  Messages = Daemon
  DirAddress = ${SERVER_IP}
}

JobDefs {
  Name = "DefaultJob"
  Type = Backup
  Level = Incremental
  Client = bacula-fd
  FileSet = "Full Set"
  Schedule = "WeeklyCycle"
  Storage = File
  Messages = Standard
  Pool = File
  SpoolAttributes = yes
  Priority = 10
  Write Bootstrap = "/var/lib/bacula/%c.bsr"
}

Job {
  Name = "BackupClient1"
  JobDefs = "DefaultJob"
}

# SERVICIO: Trabajo crítico que respalda la propia base de datos (Catálogo) 
# de Bacula. Sin esto, un desastre mayor impediría saber qué hay en los volúmenes.
Job {
  Name = "BackupCatalog"
  JobDefs = "DefaultJob"
  Level = Full
  FileSet="Catalog"
  Schedule = "WeeklyCycleAfterBackup"
  RunBeforeJob = "/etc/bacula/scripts/make_catalog_backup.pl MyCatalog"
  RunAfterJob  = "/etc/bacula/scripts/delete_catalog_backup"
  Write Bootstrap = "/var/lib/bacula/%n.bsr"
  Priority = 11
}

Job {
  Name = "RestoreFiles"
  Type = Restore
  Client = bacula-fd
  Storage = File
  FileSet = "Full Set"
  Pool = File
  Messages = Standard
  Where = /nonexistent/path/to/file/archive/dir/bacula-restores
}

FileSet {
  Name = "Full Set"
  Include {
    Options {
      signature = MD5
    }
    File = /usr/sbin
  }
  Exclude {
    File = /var/lib/bacula
    File = /proc
    File = /tmp
    File = /sys
    File = /.journal
    File = /.fsck
  }
}

Schedule {
  Name = "WeeklyCycle"
  Run = Full 1st sun at 23:05
  Run = Differential 2nd-5th sun at 23:05
  Run = Incremental mon-sat at 23:05
}

Schedule {
  Name = "WeeklyCycleAfterBackup"
  Run = Full sun-sat at 23:10
}

FileSet {
  Name = "Catalog"
  Include {
    Options {
      signature = MD5
    }
    File = "/var/lib/bacula/bacula.sql"
  }
}

Client {
  Name = bacula-fd
  Address = ${SERVER_IP}
  FDPort = 9102
  Catalog = MyCatalog
  # RELACIÓN CRUZADA: El Director se autentica contra el demonio de archivos (File Daemon) 
  # del cliente utilizando esta contraseña para extraer sus datos.
  Password = "${BACULA_FD_PASSWORD}"
  File Retention = 60 days
  Job Retention = 6 months
  AutoPrune = yes
}

Storage {
  Name = File
  SDPort = 9103
  # RELACIÓN CRUZADA: El Director presenta esta clave al Storage Daemon para que 
  # le permita escribir los flujos de datos entrantes en los discos duros.
  Password = "${BACULA_SD_PASSWORD}"
  Device = FileStorage
  Media Type = File
  Address = ${SERVER_IP}
}

Catalog {
  Name = MyCatalog
  dbname = "bacula"; DB Address = "localhost"; DB Port = "3306"; dbuser = "bacula"; 
  # RELACIÓN CRUZADA: Conexión nativa con MariaDB. Esta contraseña vincula a Bacula 
  # con los esquemas SQL donde guarda nombres de archivos, permisos, volúmenes y hashes.
  dbpassword = "${DB_PASSWORD}"
}

Messages {
  Name = Standard
  mailcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula: %t %e of %c %l\" %r"
  operatorcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula: Intervention needed for %j\" %r"
  mail = root = all, !skipped
  operator = root = mount
  console = all, !skipped, !saved
  append = "/var/log/bacula/bacula.log" = all, !skipped
  catalog = all
}

Messages {
  Name = Daemon
  mailcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula daemon message\" %r"
  mail = root = all, !skipped
  console = all, !skipped, !saved
  append = "/var/log/bacula/bacula.log" = all, !skipped
}

Pool {
  Name = Default
  Pool Type = Backup
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 365 days
  Maximum Volume Bytes = 50G
  Maximum Volumes = 100
}

Pool {
  Name = File
  Pool Type = Backup
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 365 days
  Maximum Volume Bytes = 50G
  Maximum Volumes = 100
  Label Format = "Vol-"
}

Pool {
  Name = Scratch
  Pool Type = Backup
}

Console {
  Name = bacula-mon
  # RELACIÓN CRUZADA: Configuración del monitor restringido (solo lectura de estados).
  Password = "${BACULA_PASSWORD}"
  CommandACL = status, .status
}
EOF
}

# ==============================================================================
# 7. CONFIGURACIÓN DE BACULA (STORAGE DAEMON)
# ==============================================================================
configurar_bacula_sd () {
  log_info "Configurando Bacula Storage Daemon..."
  backup_file "/etc/bacula/bacula-sd.conf"
  cat << EOF > /etc/bacula/bacula-sd.conf
Storage {
  Name = bacula-sd
  SDPort = 9103
  WorkingDirectory = "/var/lib/bacula"
  Pid Directory = "/run/bacula"
  Plugin Directory = "/usr/lib/bacula"
  Maximum Concurrent Jobs = 20
  SDAddress = ${SERVER_IP}
}

# RELACIÓN CRUZADA: El SD declara quién está autorizado a enviarle datos. 
# En este caso, solo el 'bacula-dir' que presente la clave criptográfica correcta.
Director {
  Name = bacula-dir
  Password = "${BACULA_SD_PASSWORD}"
}

Director {
  Name = bacula-mon
  Password = "${BACULA_DIR_PASSWORD}"
  Monitor = yes
}

# SERVICIO: Configuración del destino final físico de los datos. En una arquitectura 
# empresarial real, esto puede apuntar a cintas LTO, cabinas iSCSI o NAS.
Device {
  Name = FileStorage
  Media Type = File
  Archive Device = /copias
  LabelMedia = yes;
  Random Access = Yes;
  AutomaticMount = yes;
  RemovableMedia = no;
  AlwaysOpen = no;
  Maximum Concurrent Jobs = 5
}

Messages {
  Name = Standard
  director = bacula-dir = all
}
EOF
}

# ==============================================================================
# 8. CONFIGURACIÓN DE BACULA (FILE DAEMON)
# ==============================================================================
configurar_bacula_fd () {
  log_info "Configurando Bacula File Daemon..."
  backup_file "/etc/bacula/bacula-fd.conf"
  cat << EOF > /etc/bacula/bacula-fd.conf
# RELACIÓN CRUZADA: El cliente local (FD) especifica que confía en el Director 
# remoto, permitiéndole extraer archivos si presenta esta contraseña estática.
Director {
  Name = bacula-dir
  Password = "${BACULA_FD_PASSWORD}"
}

Director {
  Name = bacula-mon
  Password = "${BACULA_DIR_PASSWORD}"
  Monitor = yes
}

# SERVICIO: El File Daemon corre en cada máquina que necesita ser respaldada. 
# Escucha peticiones del Director en el puerto 9102 y empaqueta los archivos requeridos.
FileDaemon {
  Name = bacula-fd
  FDport = 9102
  WorkingDirectory = /var/lib/bacula
  Pid Directory = /run/bacula
  Maximum Concurrent Jobs = 20
  Plugin Directory = /usr/lib/bacula
  FDAddress = ${SERVER_IP}
}

Messages {
  Name = Standard
  director = bacula-dir = all, !skipped, !restored, !verified, !saved
}
EOF
}

# ==============================================================================
# 9. CONFIGURACIÓN DE BACULA (BCONSOLE)
# ==============================================================================
configurar_bacula_bconsole () {
  log_info "Configurando Bacula Console..."
  backup_file "/etc/bacula/bconsole.conf"
  cat << EOF > /etc/bacula/bconsole.conf
Director {
  Name = bacula-dir
  DIRport = 9101
  address = ${SERVER_IP}
  # RELACIÓN CRUZADA: Autenticación de bconsole (la interfaz de línea de comandos). 
  # Utiliza la llave principal para gobernar el Director.
  Password = "${BACULA_DIR_PASSWORD}"
}
EOF
}

# ==============================================================================
# 10. REINICIAR Y VERIFICAR SERVICIOS 
# ==============================================================================
reiniciar_verificar_servicios () {
  log_info "Reiniciando y verificando servicios de Bacula..."
  systemctl restart bacula-sd bacula-dir bacula-fd
  systemctl status bacula-sd bacula-dir bacula-fd --no-pager
}

# ==============================================================================
# 11. EJECUCIÓN DE FUNCIONES PRINCIPALES
# ==============================================================================
verificar_privilegios
recoleccion_variables
instalacion_dependencias
preparacion_directorio
configurar_bacula_dir
configurar_bacula_sd
configurar_bacula_fd
configurar_bacula_bconsole
reiniciar_verificar_servicios

log_info "Instalación y configuración de Bacula Server completada exitosamente."
log_info "Accede a Webmin en: https://${SERVER_IP}:10000"