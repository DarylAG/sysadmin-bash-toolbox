#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Instalación y configuración automatizada de Bacula Server 
#            (Director, SD, FD), MariaDB y Webmin.
# ==============================================================================

set -euo pipefail

log_info() {

  echo -e "\n\e[32m[INFO]\e[0m $1"

}

log_error() {

  echo -e "\n\e[31m[ERROR]\e[0m $1"

}

verificar_privilegios() {

  log_info "Verificando privilegios de administrador..."
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script requiere privilegios de administrador. Ejecútalo como root o usando sudo."
    exit 1
  fi

}

# ==============================================================================
# 1. RECOLECCIÓN DE DATOS
# ==============================================================================
# BASH: 'read' captura la entrada del usuario. 
# -r evita que las barras invertidas (\) actúen como caracteres de escape.
# -p muestra el mensaje en pantalla.
# -s oculta lo que el usuario escribe (ideal para contraseñas).

recoleccion_variables() {

  log_info "Recolección de variables dinámicas..."
  read -r -p "Ingrese la IP del servidor (ej: 192.168.106.1): " SERVER_IP
  read -r -s -p "Ingrese la contraseña para Bacula/MySQL: " BACULA_PASSWORD


  if [ -z "$SERVER_IP" ] || [ -z "$BACULA_PASSWORD" ]; then

    log_error "Error: La IP y la contraseña son obligatorias."
    exit 1

  fi
  
}

# ==============================================================================
# 2. INSTALACIÓN DE DEPENDENCIAS Y SERVICIOS BASE
# ==============================================================================
instalacion_dependencias() {

  # SERVICIO (Bacula): El ecosistema de Bacula se divide en varios demonios:
  # - Director (bacula-dir): El cerebro. Controla las tareas y catálogos. 
  # - Storage (bacula-sd): Gestiona el almacenamiento físico (discos, cintas).
  # - File (bacula-fd): El cliente que se instala en la máquina a respaldar.
  # - Console (bconsole): La herramienta para interactuar con el Director.

  log_info "Actualizando repositorios e instalando dependencias..."
  apt update && apt upgrade -y
  apt install apache2 mariadb-server mariadb-client php -y
  apt install bacula bacula-client bacula-common-mysql bacula-director-mysql bacula-sd bacula-server bacula-tray-monitor -y
  apt install perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions libdbd-mysql-perl wget -y


  # ==============================================================================
  # 4. INSTALACIÓN DE WEBMIN (INTERFAZ GRÁFICA)
  # ==============================================================================
  log_info "Instalando Webmin..."
  cd /tmp
  wget -q https://sourceforge.net/projects/webadmin/files/webmin/2.670/webmin_2.670_all.deb -O webmin_2.670_all.deb
  dpkg -i webmin_2.670_all.deb || apt-get install -f -y

}

# ==============================================================================
# 5. PREPARACIÓN DEL DIRECTORIO DE RESPALDOS
# ==============================================================================
preparacion_directorio() {
  
  log_info "Preparando directorio de respaldos" 
  mkdir -p /copias
  chmod 777 /copias

}

# ==============================================================================
# 6. CONFIGURACIÓN DE BACULA (DIRECTOR, STORAGE Y FILE DAEMON)
# ==============================================================================
# BASH: Redirigimos errores (2>/dev/null) si el archivo original no existe, 
# y '|| true' evita que el script se detenga por el 'set -e'.
configurar_bacula_dir () {
  
  log_info "Configurando Bacula Director..."
  cp /etc/bacula/bacula-dir.conf /etc/bacula/bacula-dir.conf.bak 2>/dev/null || true
  cat << EOF > /etc/bacula/bacula-dir.conf
Director {
  Name = bacula-dir
  DIRport = 9101
  QueryFile = "/etc/bacula/scripts/query.sql"
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 20
  Password = "${BACULA_PASSWORD}"
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
  Password = "${BACULA_PASSWORD}"
  File Retention = 60 days
  Job Retention = 6 months
  AutoPrune = yes
}

Storage {
  Name = File
  SDPort = 9103
  Password = "${BACULA_PASSWORD}"
  Device = FileStorage
  Media Type = File
  Address = ${SERVER_IP}
}

Catalog {
  Name = MyCatalog
  dbname = "bacula"; DB Address = "localhost"; DB Port = "3306"; dbuser = "bacula"; dbpassword = "${BACULA_PASSWORD}"
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
  cp /etc/bacula/bacula-sd.conf /etc/bacula/bacula-sd.conf.bak 2>/dev/null || true
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

Director {
  Name = bacula-dir
  Password = "${BACULA_PASSWORD}"
}

Director {
  Name = bacula-mon
  Password = "${BACULA_PASSWORD}"
  Monitor = yes
}

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
# 8. Configuración de /etc/bacula/bacula-fd.conf
# ==============================================================================
configurar_bacula_fd () {
  
  log_info "Configurando Bacula File Daemon..."

  cp /etc/bacula/bacula-fd.conf /etc/bacula/bacula-fd.conf.bak 2>/dev/null || true

  cat << EOF > /etc/bacula/bacula-fd.conf
Director {
  Name = bacula-dir
  Password = "${BACULA_PASSWORD}"
}

Director {
  Name = bacula-mon
  Password = "${BACULA_PASSWORD}"
  Monitor = yes
}

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
# 9. Configuración de /etc/bacula/bconsole.conf
# ==============================================================================
configurar_bacula_bconsole () {
  
  log_info "Configurando Bacula Console..."
  cp /etc/bacula/bconsole.conf /etc/bacula/bconsole.conf.bak 2>/dev/null || true

  cat << EOF > /etc/bacula/bconsole.conf
Director {
  Name = bacula-dir
  DIRport = 9101
  address = ${SERVER_IP}
  Password = "${BACULA_PASSWORD}"
}
EOF

}

# ==============================================================================
# 10. Reiniciar y verificar servicios 
# ==============================================================================
reiniciar_verificar_servicios () {
  
  log_info "Reiniciando y verificando servicios de Bacula..."
  systemctl restart bacula-sd bacula-dir bacula-fd
  systemctl status bacula-sd bacula-dir bacula-fd --no-pager

}

# ==============================================================================
# 11. Ejecución de funciones principales
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
