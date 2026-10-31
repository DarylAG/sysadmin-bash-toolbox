#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Instalación y configuración automatizada del Cliente Bacula (FD)
# ==============================================================================

set -euo pipefail

log_info() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

verificar_privilegios() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script requiere privilegios de administrador. Ejecútalo como root o usando sudo."
    exit 1
  fi
}

recoleccion_variables() {
  log_info "Configuración de Variables"
  DIRECTOR_NAME="bacula-dir"
  CLIENT_NAME="$(hostname)-fd"
  
  read -r -s -p "Ingrese la contraseña para Bacula Director: " BACULA_PASSWORD
  echo "" # Salto de línea estético tras presionar Enter

  if [[ -z "$BACULA_PASSWORD" ]]; then
    log_error "La contraseña no puede estar vacía."
    exit 1
  fi
}

instalar_paquetes() {
  log_info "Actualizando e instalando bacula-fd..."
  #export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y bacula-fd
}

configurar_bacula_fd() {
  log_info "Configurando el cliente Bacula (/etc/bacula/bacula-fd.conf)..."
  cp /etc/bacula/bacula-fd.conf /etc/bacula/bacula-fd.conf.bak 2>/dev/null || true

  cat << EOF > /etc/bacula/bacula-fd.conf
FileDaemon {
  Name = ${CLIENT_NAME}
  FDport = 9102
  WorkingDirectory = /var/lib/bacula
  Pid Directory = /run/bacula
  Maximum Concurrent Jobs = 20
  Plugin Directory = /usr/lib/bacula
}

Director {
  Name = ${DIRECTOR_NAME}
  Password = "${BACULA_PASSWORD}"
}

Director {
  Name = bacula-mon
  Password = "${BACULA_PASSWORD}"
  Monitor = yes
}

Messages {
  Name = Standard
  director = ${DIRECTOR_NAME} = all, !skipped, !restored, !verified, !saved
}
EOF
}

configurar_firewall() {
  log_info "Ajustando Firewall (ufw)..."
  if command -v ufw > /dev/null; then
      ufw allow 9102/tcp
  else
      log_info "UFW no está instalado, omitiendo regla de firewall..."
  fi
}

reiniciar_servicios() {
  log_info "Reiniciando y habilitando bacula-fd..."
  systemctl restart bacula-fd
  systemctl enable bacula-fd
  
  echo -e "\n=========================================================="
  echo "¡Configuración del Cliente Bacula completada exitosamente!"
  echo "Nombre del cliente configurado: $CLIENT_NAME"
  echo "=========================================================="
  systemctl status bacula-fd --no-pager
}

# ==============================================================================
# EJECUCIÓN PRINCIPAL
# ============================================================================== 
verificar_privilegios
recoleccion_variables
instalar_paquetes
configurar_bacula_fd
configurar_firewall
reiniciar_servicios