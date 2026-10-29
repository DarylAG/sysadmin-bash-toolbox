#!/bin/bash
# ==============================================================================
# Automatización de Infraestructura DDNS (BIND9 + Kea DHCP) con Instalación
# ==============================================================================
# Autor: Daril Arias
# Fecha: 10/2026
# Descripción: Automatización del despliegue de un servidor DDNS para los 
# laboratorios de telemática en el Instituto Nacional de Aprendizaje (INA).
# ==============================================================================

# Validar ejecución con privilegios de superusuario (root)
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root o usando sudo."
  exit 1
fi

# ==============================================================================
# FASE 1: RECOLECCIÓN DE DATOS (Interacción)
# En esta fase el servidor aún utiliza DHCP (NAT) para mantener conexión a Internet.
# ==============================================================================
echo "=== Fase 1: Configuración de Variables del Sistema DDNS ==="

read -r -p "Nombre del Dominio (ej. lab.local): " DOMINIO
read -r -p "Hostname primario del DNS (ej. ns1): " HOSTNAME_PRIMARIO
read -r -p "IP estática para el Servidor DNS/DHCP (ej. 192.168.1.10): " IP_SERVIDOR
read -r -p "Último octeto de la IP del servidor (ej. 10): " OCTETO_IP
read -r -p "Máscara de red en formato decimal (ej. 255.255.255.0): " MASCARA_RED
read -r -p "Subred en formato CIDR para BIND/Kea (ej. 192.168.1.0/24): " SUBRED_CIDR
read -r -p "Octetos de Zona Inversa (ej. 1.168.192 para 192.168.1.x): " ZONA_INVERSA_ARPA
read -r -p "Interfaz de Red a configurar (ej. eth0 o enp0s3): " INTERFAZ_RED
read -r -p "Rango de IPs para DHCP (ej. 192.168.1.100 - 192.168.1.200): " RANGO_DHCP
read -r -p "IP del Gateway/Router: " IP_GATEWAY
read -r -p "Nombre de la llave TSIG para actualizaciones dinámicas (ej. ddns-key): " NOMBRE_LLAVE_TSIG

# ==============================================================================
# FASE 2: APROVISIONAMIENTO (Dependencia de Internet)
# Descarga de todos los paquetes necesarios antes de aislar el servidor.
# ==============================================================================
echo "=== Fase 2: Instalación de Paquetes Requeridos ==="
apt-get update
apt-get install -y bind9 bind9utils bind9-doc dnsutils curl apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-2/setup.deb.sh' | bash
apt-get install -y isc-kea-dhcp4-server isc-kea-dhcp-ddns-server

# Función para realizar copias de seguridad antes de modificar un archivo original
backup_file() {
    local FILE=$1
    if [ -f "$FILE" ]; then
        local BACKUP_NAME
        BACKUP_NAME="${FILE}.bak_$(date +%F)"
        cp -a "$FILE" "$BACKUP_NAME"
        echo "[Backup] Creado: $BACKUP_NAME"
    fi
}

# ==============================================================================
# FASE 3: CONFIGURACIÓN DE SERVICIOS (Preparación en frío)
# Se inyectan las configuraciones, pero los servicios aún no se inician.
# ==============================================================================
echo "=== Fase 3: Configurando BIND9 y Kea DHCP ==="

# 3.1 Opciones globales de BIND9 (Seguridad y resolución)
backup_file "/etc/bind/named.conf.options"
cat << EOF > "/etc/bind/named.conf.options"
// Definir subredes con permisos para consultar este DNS
acl trusted {
        localhost;
        localnets;
        ${SUBRED_CIDR};
};

options {
        directory "/var/cache/bind";
        recursion yes;
        
        allow-query { trusted; };
        allow-query-cache { trusted; };
        allow-recursion { trusted; };

        // Servidores raíz para resolución externa
        forwarders{
                8.8.8.8;
                8.8.4.4;
        };
        
        dnssec-validation auto;
        listen-on-v6 port 53 { ::1; };
        // El servidor escucha en su loopback y en su futura IP estática
        listen-on port 53 { 127.0.0.1; ${IP_SERVIDOR}; };
};
EOF

# 3.2 Declaración de Zonas DNS e integración de llave TSIG
backup_file "/etc/bind/named.conf.local"
cat << EOF > "/etc/bind/named.conf.local"
include "/etc/bind/${NOMBRE_LLAVE_TSIG}.key";

zone "${DOMINIO}" {
    type master;
    file "/var/lib/bind/db.${DOMINIO}";
    update-policy {
        grant ${NOMBRE_LLAVE_TSIG} wildcard *.${DOMINIO} A DHCID;
    };
};

zone "${ZONA_INVERSA_ARPA}.in-addr.arpa" {
    type master;
    file "/var/lib/bind/db.${ZONA_INVERSA_ARPA}";    
    update-policy {
        grant ${NOMBRE_LLAVE_TSIG} wildcard *.${ZONA_INVERSA_ARPA}.in-addr.arpa PTR DHCID;
   };
};
EOF

# 3.3 Creación de archivos de zona (Directa)
mkdir -p /var/lib/bind
backup_file "/var/lib/bind/db.${DOMINIO}"
cat << EOF > "/var/lib/bind/db.${DOMINIO}"
\$TTL 604800    ; 1 week
${DOMINIO}.     IN SOA  ${HOSTNAME_PRIMARIO}.${DOMINIO}. admin.${DOMINIO}. (
                $(date +%Y%m%d)01 ; serial
                604800     ; refresh 
                86400      ; retry 
                2419200    ; expire 
                604800     ; minimum 
                )
            NS  ${HOSTNAME_PRIMARIO}.${DOMINIO}.
${HOSTNAME_PRIMARIO}.${DOMINIO}.        A   ${IP_SERVIDOR}
EOF

# 3.4 Creación de archivos de zona (Inversa)
backup_file "/var/lib/bind/db.${ZONA_INVERSA_ARPA}"
cat << EOF > "/var/lib/bind/db.${ZONA_INVERSA_ARPA}"
\$TTL 604800    ; 1 week
${ZONA_INVERSA_ARPA}.in-addr.arpa. IN SOA ${HOSTNAME_PRIMARIO}.${DOMINIO}. admin.${DOMINIO}. (
                $(date +%Y%m%d)01 ; serial
                604800     ; refresh 
                86400      ; retry 
                2419200    ; expire 
                604800     ; minimum 
                )
            NS  ${HOSTNAME_PRIMARIO}.${DOMINIO}.
${OCTETO_IP}.${ZONA_INVERSA_ARPA}.in-addr.arpa. PTR    ${HOSTNAME_PRIMARIO}.${DOMINIO}.
EOF

# 3.5 Configuración del daemon principal de DHCP (Kea IPv4)
backup_file "/etc/kea/kea-dhcp4.conf"
cat << EOF > "/etc/kea/kea-dhcp4.conf"
{
"Dhcp4": {
    "interfaces-config": {
        "interfaces": ["${INTERFAZ_RED}"]
    },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv",
        "lfc-interval": 3600
    },
    "renew-timer": 15840,
    "rebind-timer": 27720,
    "valid-lifetime": 31680,
    "dhcp-ddns": {
        "enable-updates": true
    },
    "ddns-qualifying-suffix": "${DOMINIO}",
    "ddns-override-client-update": true,
    "subnet4": [
        {
            "id": 1,
            "subnet": "${SUBRED_CIDR}",
            "pools": [ { "pool": "${RANGO_DHCP}" } ],
            "option-data": [
                { "name": "routers", "data": "${IP_GATEWAY}" },
                { "name": "domain-name-servers", "data": "${IP_SERVIDOR}" },
                { "name": "domain-search", "data": "${DOMINIO}" }
            ]
        }
    ]
}
}
EOF

# 3.6 Configuración del módulo de actualización DDNS de Kea
backup_file "/etc/kea/kea-dhcp-ddns.conf"
cat << EOF > "/etc/kea/kea-dhcp-ddns.conf"
{
"DhcpDdns":
{
  "ip-address": "127.0.0.1",
  "port": 53001,
  "control-socket": {
      "socket-type": "unix",
      "socket-name": "/var/run/kea/kea-ddns-ctrl-socket"
  },
  <?include "/etc/kea/tsig-keys.json"?>
  "forward-ddns" : {
      "ddns-domains" : [
          {
               "name": "${DOMINIO}.",
               "key-name": "${NOMBRE_LLAVE_TSIG}",
               "dns-servers": [ { "ip-address": "${IP_SERVIDOR}" } ]
          }
      ]
  },
  "reverse-ddns" : {
      "ddns-domains" : [
          {
               "name": "${ZONA_INVERSA_ARPA}.in-addr.arpa.",
               "key-name": "${NOMBRE_LLAVE_TSIG}",
               "dns-servers": [ { "ip-address": "${IP_SERVIDOR}" } ]
          }
      ]
  }
}
}
EOF

# ==============================================================================
# FASE 3.7: GENERACIÓN Y CONFIGURACIÓN AUTOMATIZADA DE LLAVES TSIG
# ==============================================================================
echo "=== Generando Llave TSIG y Ajustando Permisos ==="

# 1. Generar la llave criptográfica en BIND9
tsig-keygen -a HMAC-SHA256 "$NOMBRE_LLAVE_TSIG" > "/etc/bind/${NOMBRE_LLAVE_TSIG}.key"

# 2. Extraer limpiamente el secreto base64 a un archivo independiente para Kea (Referencia: DDNS_Kea_BIND9.md)
awk -F'"' '/secret/ {printf "%s", $2}' "/etc/bind/${NOMBRE_LLAVE_TSIG}.key" > "/etc/kea/${NOMBRE_LLAVE_TSIG}.secret"

# 3. Crear el archivo tsig-keys.json utilizando la directiva "secret-file" exigida por Kea
cat << EOF > /etc/kea/tsig-keys.json
    "tsig-keys": [
        {
           "name": "${NOMBRE_LLAVE_TSIG}",
           "algorithm": "hmac-sha256",
           "secret-file": "/etc/kea/${NOMBRE_LLAVE_TSIG}.secret"
        }
    ],

EOF

# 4. Asignar propietarios y permisos restrictivos de seguridad (640)[cite: 7]
chown -R bind:bind /etc/bind/
chown -R bind:bind /var/lib/bind/
chmod 640 "/etc/bind/${NOMBRE_LLAVE_TSIG}.key"

chown _kea:_kea /etc/kea/tsig-keys.json "/etc/kea/${NOMBRE_LLAVE_TSIG}.secret"
chmod 640 /etc/kea/tsig-keys.json "/etc/kea/${NOMBRE_LLAVE_TSIG}.secret"
chown -R _kea:_kea /etc/kea/


chown _kea:_kea /etc/kea/tsig-keys.json
chmod 640 "/etc/kea/tsig-keys.json"

# ==============================================================================
# FASE 4: MUTACIÓN DEL SISTEMA OPERATIVO
# Transformación de la máquina hacia su estado definitivo (Self-Resolution).
# ==============================================================================
echo "=== Fase 4: Configuración del Sistema Operativo ==="

# Aplicar hostname en memoria
hostnamectl set-hostname "${HOSTNAME_PRIMARIO}"

# Mapear FQDN local para que los servicios se identifiquen a sí mismos
backup_file "/etc/hosts"
cat << EOF > "/etc/hosts"
127.0.0.1       localhost
127.0.1.1       ${HOSTNAME_PRIMARIO}
${IP_SERVIDOR}  ${HOSTNAME_PRIMARIO}.${DOMINIO} ${HOSTNAME_PRIMARIO}
EOF

# Apuntar el cliente DNS del servidor hacia sí mismo (loopback)
backup_file "/etc/resolv.conf"
cat << EOF > "/etc/resolv.conf"
domain ${DOMINIO}
search ${DOMINIO}
nameserver 127.0.0.1
EOF

# Transición del adaptador de red a configuración estática
backup_file "/etc/network/interfaces"
cat << EOF > "/etc/network/interfaces"
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Configuración estática que aplicará en el próximo arranque
auto ${INTERFAZ_RED}
iface ${INTERFAZ_RED} inet static
    address ${IP_SERVIDOR}
    netmask ${MASCARA_RED}
    gateway ${IP_GATEWAY}
EOF

# ==============================================================================
# FASE 5: VALIDACIÓN, HABILITACIÓN Y APAGADO AUTOMÁTICO (Cutover)
# ==============================================================================
echo "=== Fase 5: Validación y Cierre ==="

named-checkconf /etc/bind/named.conf
named-checkzone "${DOMINIO}" "/var/lib/bind/db.${DOMINIO}"
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
systemctl restart named isc-kea-dhcp4-server isc-kea-dhcp-ddns-server
systemctl enable named isc-kea-dhcp4-server isc-kea-dhcp-ddns-server
# Configurar demonios para inicio automático en el próximo arranque


echo ""
echo "=================================================================="
echo "¡APROVISIONAMIENTO DDNS COMPLETADO CON ÉXITO!"
echo "=================================================================="
echo "El servidor se apagará automáticamente en 10 segundos."
echo "PASOS A SEGUIR EN EL HIPERVISOR:"
echo "1. Cambia el adaptador de red '${INTERFAZ_RED}' de 'NAT' a 'Red Interna'."
echo "2. Vuelve a encender la máquina virtual."
echo "Al arrancar, el servidor ya tendrá la IP ${IP_SERVIDOR}, su propio DNS"
echo "activo, y estará listo para repartir direccionamiento en el laboratorio."
echo "=================================================================="

sleep 10
poweroff