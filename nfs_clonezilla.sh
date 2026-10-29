#!/bin/bash

echo "Instalando nfs-kernel-server..."
apt-get update
apt-get install -y nfs-kernel-server

echo "Formateando el nuevo disco..."
mkfs.ext4 /dev/sdb

echo "Creando el directorio principal para las imágenes de Clonezilla..."
mkdir -p /srv/nfs/clonezilla

echo "Obteniendo el UUID del nuevo disco y configurando /etc/fstab..."
# Extraemos el UUID exacto para un montaje seguro
DISCO_UUID=$(blkid -s UUID -o value /dev/sdb)

# Añadimos la entrada a fstab para que el montaje sea permanente tras reiniciar
echo "UUID=$DISCO_UUID    /srv/nfs/clonezilla    ext4    defaults    0    2" >> /etc/fstab

echo "Montando el disco..."
mount -a

echo "Asignando permisos abiertos al disco montado..."
# Es vital hacer esto DESPUÉS de montar el disco, o los permisos no se aplicarán al nuevo volumen
chown -R nobody:nogroup /srv/nfs/clonezilla
chmod -R 777 /srv/nfs/clonezilla

echo "Configurando /etc/exports..."
cat <<EOF > /etc/exports
# Directorio único para imágenes de Clonezilla/DRBL
/srv/nfs/clonezilla 192.168.100.0/24(rw,sync,no_root_squash,no_subtree_check)
EOF

echo "Aplicando configuración y reiniciando el servicio NFS..."
exportfs -arv
systemctl daemon-reload
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

echo "¡Servidor NFS listo con almacenamiento externo!"