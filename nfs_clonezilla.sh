#!/bin/bash
# ==============================================================================
# Autor: [Tu Nombre/Administrador]
# Fecha: Octubre 2026
# Propósito: Automatización del Servidor NFS (Almacenamiento para Clonezilla)
# Estándar:  Modelo de arquitectura, seguridad y relaciones cruzadas.
# ==============================================================================

# SEGURIDAD: Detiene la ejecución si ocurre un error o si se utiliza una variable no declarada.
# Previene formateos accidentales en discos equivocados en caso de variables vacías.
set -euo pipefail

log_info() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

log_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

# ==============================================================================
# FASE 0: VERIFICACIÓN Y RESPALDOS
# ==============================================================================
verificar_privilegios() {
    # SEGURIDAD: El formateo de bloques (mkfs) y la modificación de la tabla 
    # de particiones virtual (/etc/fstab) requieren acceso irrestricto al sistema.
    if [ "$EUID" -ne 0 ]; then
        log_error "Error: Este script debe ser ejecutado como root."
        exit 1
    fi
}

backup_file() {
    # SERVICIO: Preservación de configuraciones críticas como fstab o exports 
    # para permitir recuperación en caso de fallos en el despliegue.
    local FILE="$1"
    if [ -f "$FILE" ]; then
        cp -a "$FILE" "${FILE}.bak_$(date +%F)"
        log_info "[Backup] Creado: ${FILE}.bak_$(date +%F)"
    fi
}

# ==============================================================================
# FASE 1: RECOLECCIÓN DE VARIABLES
# ==============================================================================
recoleccion_variables() {
    log_info "--- Configuración del Entorno de Almacenamiento ---"
    read -r -p "Ruta del disco nuevo a formatear (ej. /dev/sdb): " DISCO_OBJETIVO
    read -r -p "Directorio de montaje principal (ej. /srv/nfs/clonezilla): " RUTA_MONTAJE
    read -r -p "Subred permitida para acceso NFS (ej. 192.168.100.0/24): " SUBRED_NFS
    
    if [[ -z "$DISCO_OBJETIVO" || -z "$RUTA_MONTAJE" || -z "$SUBRED_NFS" ]]; then
        log_error "Todas las variables son obligatorias. Abortando."
        exit 1
    fi
}

# ==============================================================================
# FASE 2: APROVISIONAMIENTO DE PAQUETES
# ==============================================================================
instalar_paquetes() {
    log_info "Instalando motor NFS..."
    apt-get update
    
    # SERVICIO: Instalación del componente a nivel de kernel para compartir 
    # sistemas de archivos a alta velocidad a través de la red local.
    apt-get install -y nfs-kernel-server
}

# ==============================================================================
# FASE 3: PREPARACIÓN DEL ALMACENAMIENTO FÍSICO
# ==============================================================================
preparar_almacenamiento() {
    log_info "Formateando el bloque de almacenamiento ($DISCO_OBJETIVO)..."
    # SEGURIDAD: Proceso destructivo. Se formatea el volumen con sistema de 
    # archivos ext4 (estable y compatible con ACLs estándar de Linux).
    mkfs.ext4 -F "$DISCO_OBJETIVO"

    log_info "Construyendo y asegurando el punto de montaje..."
    # SERVICIO: Generación de la ruta estructural definida en la arquitectura.
    mkdir -p "$RUTA_MONTAJE"

    # RELACIÓN CRUZADA: Extracción del UUID criptográfico/físico. Permite que el 
    # sistema monte siempre la unidad correcta sin importar si cambia su ruta en `/dev/`.
    local DISCO_UUID
    DISCO_UUID=$(blkid -s UUID -o value "$DISCO_OBJETIVO")

    backup_file "/etc/fstab"
    log_info "Inyectando reglas de persistencia en /etc/fstab..."
    echo "UUID=$DISCO_UUID    $RUTA_MONTAJE    ext4    defaults    0    2" >> /etc/fstab

    # SERVICIO: Montaje dinámico para disponer de la unidad en memoria de inmediato.
    mount -a

    # SEGURIDAD: Alteración profunda de permisos POSIX. Se exige permisos abiertos (777) 
    # y mapeo anónimo (nobody:nogroup) tras el montaje, para que clientes DRBL/Clonezilla 
    # no experimenten colisiones de propiedad (UID/GID) al inyectar imágenes.
    log_info "Asignando permisos granulares al volumen aprovisionado..."
    chown -R nobody:nogroup "$RUTA_MONTAJE"
    chmod -R 777 "$RUTA_MONTAJE"
}

# ==============================================================================
# FASE 4: DESPLIEGUE Y CONFIGURACIÓN DE EXPORTACIONES NFS
# ==============================================================================
configurar_nfs() {
    log_info "Configurando el plano de exportaciones en /etc/exports..."
    backup_file "/etc/exports"
    
    cat <<EOF > /etc/exports
# SERVICIO: Punto de exportación de red exclusivo para almacenamiento Clonezilla/DRBL.
# SEGURIDAD: 'no_root_squash' permite a los clientes con privilegios root (DRBL) 
# conservar su nivel de acceso sobre NFS, necesario para crear el esqueleto de las imágenes.
$RUTA_MONTAJE $SUBRED_NFS(rw,sync,no_root_squash,no_subtree_check)
EOF
}

# ==============================================================================
# FASE 5: VALIDACIÓN, RECARGA Y HABILITACIÓN DE SERVICIOS
# ==============================================================================
verificar_sintaxis_reiniciar() {
    log_info "Aplicando reconfiguración al plano de control NFS..."
    # SERVICIO: Sincroniza la tabla interna de exportaciones del demonio NFS 
    # leyendo la nueva inyección en /etc/exports.
    exportfs -arv
    
    systemctl daemon-reload
    systemctl restart nfs-kernel-server
    systemctl enable nfs-kernel-server

    log_info "=========================================================="
    log_info "¡Servidor NFS (Clonezilla) desplegado y aprovisionado!"
    log_info "Almacenamiento: $DISCO_OBJETIVO montado en $RUTA_MONTAJE"
    log_info "Subred de acceso permitida: $SUBRED_NFS"
    log_info "=========================================================="
}

# ==============================================================================
# EJECUCIÓN PRINCIPAL (Orquestación de Fases)
# ==============================================================================
verificar_privilegios
recoleccion_variables
instalar_paquetes
preparar_almacenamiento
configurar_nfs
verificar_sintaxis_reiniciar