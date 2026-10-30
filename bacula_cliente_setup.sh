
#!/bin/bash
set -e

# 1. Variables
DIRECTOR_NAME="bacula-dir"
CLIENT_NAME="$(hostname)-fd"

# Solicitar la contraseña de forma segura (no se mostrará en pantalla)
read -r -s -p "Ingrese la contraseña para Bacula Director: " BACULA_PASSWORD
echo "" # Salto de línea estético tras presionar Enter

# 2. Instalación de paquetes mínimos (cliente solamente)
apt update && apt install -y bacula-fd

# 3. Respaldar y Reescribir Configuración
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

# 4. Ajustar Firewall (si aplica ufw)
if command -v ufw > /dev/null; then
    ufw allow 9102/tcp
fi

# 5. Reiniciar y verificar el servicio
systemctl restart bacula-fd
systemctl enable bacula-fd
systemctl status bacula-fd --no-pager

