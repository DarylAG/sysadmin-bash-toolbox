#!/bin/bash
# ==============================================================================
# Autor: Daril Arias
# Fecha: Octubre 2026
# Propósito: Instalación y configuración automatizada del Cliente Bacula (FD)
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

# SEGURIDAD: Abortar la ejecución ante variables no declaradas o errores ocultos 
# evita despliegues parciales que podrían dejar el agente de respaldos inoperante.
set -euo pipefail

log_info() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

verificar_privilegios() {
  # SEGURIDAD: La configuración del demonio de archivos (File Daemon) requiere 
  # privilegios de root para poder acceder y respaldar todo el sistema de archivos.
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script requiere privilegios de administrador. Ejecútalo como root o usando sudo."
    exit 1
  fi
}

recoleccion_variables() {
  log_info "Configuración de Variables"
  
  # SERVICIO: Nombre por defecto del ente orquestador en la arquitectura de Bacula.
  DIRECTOR_NAME="bacula-dir"
  
  # SERVICIO: Se adopta una convención de nombres basada en el hostname de la 
  # máquina seguido del sufijo '-fd' (File Daemon) para facilitar su identificación 
  # en el catálogo central.
  CLIENT_NAME="$(hostname)-fd"
  
  # RELACIÓN CRUZADA: Esta es la contraseña precompartida (PSK) que el Director 
  # configuró para este cliente. Si no coinciden, el Director no podrá extraer datos.
  read -r -s -p "Ingrese la contraseña para Bacula Director: " BACULA_PASSWORD
  echo "" 

  if [[ -z "$BACULA_PASSWORD" ]]; then
    log_error "La contraseña no puede estar vacía."
    exit 1
  fi
}

instalar_paquetes() {
  log_info "Actualizando e instalando bacula-fd..."
  # SERVICIO: En la arquitectura cliente-servidor de Bacula, los nodos a respaldar 
  # solo necesitan instalar el paquete ligero del agente (File Daemon).
  apt-get update
  apt-get install -y bacula-fd
}

configurar_bacula_fd() {
  log_info "Configurando el cliente Bacula (/etc/bacula/bacula-fd.conf)..."
  
  # SERVICIO: Resguardo de la configuración por defecto antes de inyectar la nueva.
  cp /etc/bacula/bacula-fd.conf /etc/bacula/bacula-fd.conf.bak 2>/dev/null || true

  cat << EOF > /etc/bacula/bacula-fd.conf
FileDaemon {
  # SERVICIO: Identidad de esta máquina. El Director debe tener un recurso 'Client' 
  # que coincida exactamente con este nombre.
  Name = ${CLIENT_NAME}
  FDport = 9102
  WorkingDirectory = /var/lib/bacula
  Pid Directory = /run/bacula
  Maximum Concurrent Jobs = 20
  Plugin Directory = /usr/lib/bacula
}

Director {
  Name = ${DIRECTOR_NAME}
  # RELACIÓN CRUZADA: Muro de seguridad del cliente. El Director remoto debe 
  # presentar esta clave para que el File Daemon le permita leer el disco duro local.
  Password = "${BACULA_PASSWORD}"
}

Director {
  Name = bacula-mon
  # RELACIÓN CRUZADA: Clave compartida para permitir que herramientas de 
  # monitorización (como tray-monitors) consulten el estado del agente.
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
    # SEGURIDAD: Apertura estricta del puerto RPC de Bacula FD (9102/tcp). 
    # Sin esta regla, el Director no podrá iniciar la conexión para el respaldo.
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