#!/bin/bash

set -e

# 1. Lectura de variables dinámicas
read -r -p "Ingrese la IP del servidor (ej: 192.168.106.1): " SERVER_IP
read -r -s -p "Ingrese la contraseña para Bacula/MySQL: " BACULA_PASSWORD

if [ -z "$SERVER_IP" ] || [ -z "$BACULA_PASSWORD" ]; then
  echo "Error: La IP y la contraseña son obligatorias."
  exit 1
fi

# 2. Actualización del sistema e instalación de dependencias base
apt update && apt upgrade -y
apt install apache2 mariadb-server mariadb-client php -y

# 3. Instalación de paquetes Bacula sin interrupciones manuales excesivas
apt install bacula bacula-client bacula-common-mysql bacula-director-mysql bacula-sd bacula-server bacula-tray-monitor -y

# 4. Instalación de dependencias y Webmin
apt install perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions libdbd-mysql-perl wget -y

cd /tmp
wget -q https://sourceforge.net/projects/webadmin/files/webmin/2.670/webmin_2.670_all.deb -O webmin_2.670_all.deb
dpkg -i webmin_2.670_all.deb || apt-get install -f -y

# 5. Creación y preparación del directorio de respaldos
mkdir -p /copias
chmod 777 /copias

# 6. Configuración de /etc/bacula/bacula-dir.conf
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

# 7. Configuración de /etc/bacula/bacula-sd.conf
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

# 8. Configuración de /etc/bacula/bacula-fd.conf
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

# 9. Configuración de /etc/bacula/bconsole.conf
cp /etc/bacula/bconsole.conf /etc/bacula/bconsole.conf.bak 2>/dev/null || true

cat << EOF > /etc/bacula/bconsole.conf
Director {
  Name = bacula-dir
  DIRport = 9101
  address = ${SERVER_IP}
  Password = "${BACULA_PASSWORD}"
}
EOF

# 10. Reiniciar y verificar servicios por orden
systemctl restart bacula-sd bacula-dir bacula-fd
systemctl status bacula-sd bacula-dir bacula-fd --no-pager