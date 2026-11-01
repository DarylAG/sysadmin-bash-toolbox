# Convenciones y Variables

Esta guía utiliza marcadores de posición genéricos. Antes de ejecutar los comandos o copiar las configuraciones, reemplaza los siguientes valores según tu entorno de red:

- `<HOSTNAME_PRIMARIO>`: Nombre del servidor (ej. `alpha`).

- `<DOMINIO>`: Nombre de tu dominio interno (ej. `xeon.cr`).

- `<INTERFAZ_RED>`: Interfaz de red principal (ej. `enp0s3`).

- `<IP_SERVIDOR>`: Dirección IP estática del servidor (ej. `192.168.106.1`).

- `<IP_GATEWAY>`: Dirección IP de la puerta de enlace (ej. `192.168.106.254`).

- `<SUBRED_CIDR>`: Subred en formato CIDR (ej. `192.168.106.0/24`).

- `<ZONA_INVERSA_ARPA>`: Octetos de red invertidos para la zona PTR (ej. `106.168.192`).

- `<RANGO_DHCP>`: Rango de IPs a asignar por DHCP (ej. `192.168.106.100 - 192.168.106.199`).

- `<NOMBRE_LLAVE_TSIG>`: Nombre de la llave para actualizaciones DDNS (ej. `dhcp1-alpha`).

- `<OCTETO_IP>`: Último octeto de la IP del servidor DNS/DHCP (ej. `1` o `10`).

## 1. Preparación del Sistema y Red

Configurar el nombre de host del servidor.
```bash
hostnamectl set-hostname <HOSTNAME_PRIMARIO>
```

Configurar la interfaz de red con IP estática.
```bash
nano /etc/network/interfaces
```

```bash
allow-hotplug <INTERFAZ_RED>
iface <INTERFAZ_RED> inet static
    address <IP_SERVIDOR>
    netmask 255.255.255.0
    gateway <IP_GATEWAY>
```

Actualizar el sistema base.
```bash
apt update && apt upgrade -y
```

# 2. Instalación y Configuración de BIND9 (DNS)

Instalar los paquetes requeridos para el servidor DNS.
```bash
apt install -y bind9 bind9utils bind9-doc dnsutils
```

Generar la llave TSIG para asegurar las actualizaciones dinámicas (DDNS).
```bash
cd /etc/bind
tsig-keygen <NOMBRE_LLAVE_TSIG> > <NOMBRE_LLAVE_TSIG>.key
chmod 640 <NOMBRE_LLAVE_TSIG>.key
```

Configurar las opciones globales de BIND9.
```bash
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.bak
nano /etc/bind/named.conf.options
```
```bash
// Definir red confiable
acl trusted {
        localhost;
        localnets;
        <SUBRED_CIDR>;
};

options {
        directory "/var/cache/bind";
        recursion yes;
        
        // Permisos de consulta y recursión
        allow-query { trusted; };
        allow-query-cache { trusted; };
        allow-recursion { trusted; };

        // Servidores DNS externos
        forwarders{
                8.8.8.8;
                8.8.4.4;
        };
        
        dnssec-validation auto;
        listen-on-v6 port 53 { ::1; };
        listen-on port 53 { 127.0.0.1; <IP_SERVIDOR>; };
};
```

Configurar las zonas locales permitiendo la actualización mediante la llave TSIG.
```bash
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bak
nano /etc/bind/named.conf.local
```

```bash
// Incluir la llave generada
include "/etc/bind/<NOMBRE_LLAVE_TSIG>.key";

// Zona Directa
zone "<DOMINIO>" {
    type master;
    // Las zonas deben estar en /var/lib/bind para que el usuario bind tenga permisos de escritura en DDNS
    file "/var/lib/bind/db.<DOMINIO>";
    update-policy {
        grant <NOMBRE_LLAVE_TSIG> wildcard *.<DOMINIO> A DHCID;
    };
};

// Zona Inversa
zone "<ZONA_INVERSA_ARPA>.in-addr.arpa" {
    type master;
    file "/var/lib/bind/db.<ZONA_INVERSA_ARPA>";    
    update-policy {
        grant <NOMBRE_LLAVE_TSIG> wildcard *.<ZONA_INVERSA_ARPA>.in-addr.arpa PTR DHCID;
   };
};
```

Crear el archivo de la zona directa.
```bash
nano /var/lib/bind/db.<DOMINIO>
```

```bash
$TTL 604800	; 1 week
<DOMINIO>.		IN SOA	<HOSTNAME_PRIMARIO>.<DOMINIO>. admin.<DOMINIO>. (
				2026102249 ; serial
				604800     ; refresh 
				86400      ; retry 
				2419200    ; expire 
				604800     ; minimum 
				)
			NS	<HOSTNAME_PRIMARIO>.<DOMINIO>.
<HOSTNAME_PRIMARIO>.<DOMINIO>.		A	<IP_SERVIDOR>
```

Crear el archivo de la zona inversa.
```bash
nano /var/lib/bind/db.<ZONA_INVERSA_ARPA>
```

```bash
$TTL 604800	; 1 week
<ZONA_INVERSA_ARPA>.in-addr.arpa. IN SOA <HOSTNAME_PRIMARIO>.<DOMINIO>. admin.<DOMINIO>. (
				2026101731 ; serial
				604800     ; refresh 
				86400      ; retry 
				2419200    ; expire 
				604800     ; minimum 
				)
			NS	<HOSTNAME_PRIMARIO>.<DOMINIO>.
<OCTETO_IP>.<ZONA_INVERSA_ARPA>.in-addr.arpa. PTR	<HOSTNAME_PRIMARIO>.<DOMINIO>.
```

Corregir permisos y reiniciar BIND9.
```bash
chown bind:bind /var/lib/bind/db.*
systemctl restart bind9
```


## 3. Instalación y Configuración de Kea DHCP y DDNS

Instalar el repositorio de Kea y los paquetes del servidor DHCP y DDNS.
```bash
apt install curl apt-transport-https -y
curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-2/setup.deb.sh' | bash
apt install isc-kea-dhcp4-server isc-kea-dhcp-ddns-server -y
```

Extraer el secreto TSIG de BIND9 para usarlo en Kea.
```bash
cd /etc/kea
awk -F'"' '/secret/ {printf "%s", $2}' /etc/bind/<NOMBRE_LLAVE_TSIG>.key > /etc/kea/<NOMBRE_LLAVE_TSIG>.secret
```

Configurar el archivo de llaves TSIG para Kea.
```bash
nano /etc/kea/tsig-keys.json
```

```JSON
{
    "tsig-keys": [
        {
           "name": "<NOMBRE_LLAVE_TSIG>",
           "algorithm": "hmac-sha256",
           "secret-file": "/etc/kea/<NOMBRE_LLAVE_TSIG>.secret"
        }
    ]
}
```

Aplicar permisos a las llaves.
```bash
chown _kea:_kea /etc/kea/tsig-keys.json
chmod 640 /etc/kea/tsig-keys.json
```

Configurar el módulo Kea DDNS (D2).
```bash
cp /etc/kea/kea-dhcp-ddns.conf /etc/kea/kea-dhcp-ddns.conf.bak
nano /etc/kea/kea-dhcp-ddns.conf
```

```JSON
{
"DhcpDdns":
{
  "ip-address": "127.0.0.1",
  "port": 53001,
  "control-socket": {
      "socket-type": "unix",
      "socket-name": "/var/run/kea/kea-ddns-ctrl-socket"
  },
  
  // Importar llave TSIG
  <?include "/etc/kea/tsig-keys.json"?>

  "forward-ddns" : {
      "ddns-domains" : [
          {
               "name": "<DOMINIO>.",
               "key-name": "<NOMBRE_LLAVE_TSIG>",
               "dns-servers": [ { "ip-address": "<IP_SERVIDOR>" } ]
          }
      ]
  },
  
  "reverse-ddns" : {
      "ddns-domains" : [
          {
               "name": "<ZONA_INVERSA_ARPA>.in-addr.arpa.",
               "key-name": "<NOMBRE_LLAVE_TSIG>",
               "dns-servers": [ { "ip-address": "<IP_SERVIDOR>" } ]
          }
      ]
  }
}
}
```


Configurar el servidor DHCPv4 con integración DDNS.
```bash
cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak
nano /etc/kea/kea-dhcp4.conf
```
```JSON
{
"Dhcp4": {
    "interfaces-config": {
        "interfaces": ["<INTERFAZ_RED>"]
    },

    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv",
        "lfc-interval": 3600
    },

    // Temporizadores de concesión
    "renew-timer": 15840,
    "rebind-timer": 27720,
    "valid-lifetime": 31680,

    // Habilitar actualizaciones DDNS dinámicas
    "dhcp-ddns": {
        "enable-updates": true
    },
    "ddns-qualifying-suffix": "<DOMINIO>",
    "ddns-override-client-update": true,

    "subnet4": [
        {
            "id": 1,
            "subnet": "<SUBRED_CIDR>",
            "pools": [ { "pool": "<RANGO_DHCP>" } ],
            "option-data": [
                { "name": "routers", "data": "<IP_GATEWAY>" },
                { "name": "domain-name-servers", "data": "<IP_SERVIDOR>" },
                { "name": "domain-search", "data": "<DOMINIO>" }
            ]
        }
    ]
}
}
```

Reiniciar y habilitar los servicios de Kea.
```bash
systemctl restart isc-kea-dhcp-ddns-server
systemctl restart isc-kea-dhcp4-server
systemctl enable isc-kea-dhcp-ddns-server isc-kea-dhcp4-server
```


# 4. Gestión, Verificación y Troubleshooting

## Comandos de Control de Servicios
```bash
systemctl start/stop/restart/status bind9
systemctl start/stop/restart/status isc-kea-dhcp4-server
systemctl start/stop/restart/status isc-kea-dhcp-ddns-server
```

## Comandos de Verificación de Sintaxis

Para validar la configuración de DNS (BIND9):
```bash
named-checkconf
named-checkzone <DOMINIO> /var/lib/bind/db.<DOMINIO>
named-checkzone <ZONA_INVERSA_ARPA>.in-addr.arpa /var/lib/bind/db.<ZONA_INVERSA_ARPA>
```

Para validar los archivos de configuración JSON de Kea:
```bash
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
kea-dhcp-ddns -t /etc/kea/kea-dhcp-ddns.conf
```

## Mantenimiento de Zonas DDNS (BIND9)

Antes de modificar manualmente un archivo de zona que está siendo actualizado dinámicamente, pausa las actualizaciones:
```bash
rndc freeze <DOMINIO>
```

Una vez realizados los cambios, reanuda las actualizaciones:
```bash
rndc thaw <DOMINIO>
```

### Troubleshooting y Logs

Visualizar los logs del servicio DHCP en tiempo real:
```bash
journalctl -u isc-kea-dhcp4-server.service -e --no-pager
```

Verificar la base de datos de concesiones (leases) en Kea:
```bash
more /var/lib/kea/kea-leases4.csv
```

# 5. Funciones Avanzadas y Próximos Pasos

- **Implementación de DNSSEC**: Firmar criptográficamente las zonas para garantizar la integridad y autenticidad de las respuestas DNS.
    
- **Alta Disponibilidad (HA)**: Configurar un servidor BIND9 secundario (esclavo) con transferencias de zona (`AXFR`) y establecer el esquema de alta disponibilidad nativo de Kea DHCP para redundancia activa-pasiva o activa-activa.
    
- **Base de datos backend para Kea**: Migrar el almacenamiento de concesiones (leases) del archivo CSV en memoria a un motor relacional sólido (como PostgreSQL o MySQL) para entornos empresariales escalables.