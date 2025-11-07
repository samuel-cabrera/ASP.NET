#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Despliegue de Webapp Go con systemd en Ubuntu 24.04
# =========================================================
#
# El fichero main.go con el código de la app debe estar en la misma carpeta
# ---------- Config ----------
INSTALL_DIR="/opt/gowebapp"          # Carpeta de despliegue
APP_BIN="gowebapp"                   # Nombre del binario
APP_PORT="8080"                      # Puerto de escucha
MODULE_PATH="goapp.example.com"      # Cambia si quieres
SERVICE_NAME="gowebapp.service"
ENV_FILE="/etc/default/gowebapp"
APP_USER="gowebapp"                  # Usuario del servicio

log() { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
require_root() { [[ $EUID -eq 0 ]] || { echo "[ERROR] Ejecuta este script como root o con sudo."; exit 1; }; }

# 0) Requisitos
require_root

# 1) Instalar Go
log "Actualizando sistema e instalando Go…"
apt update
apt upgrade -y
apt install -y golang curl ca-certificates

log "Verificando Go instalado…"
go version

# 2) Usuario del servicio
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  log "Creando usuario del servicio: $APP_USER"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

# 3) Proyecto
log "Creando directorio de instalación en $INSTALL_DIR…"
mkdir -p "$INSTALL_DIR"

log "copiando main.go…"
if ! [ -f main.go ]; then
  log "No existe main.go. Debe estar en la misma carpeta que el script"
  exit 1
fi
cp main.go "$INSTALL_DIR"

cd "$INSTALL_DIR"

# 4) Módulo y build (¡aquí está el arreglo!)
log "Inicializando módulo y resolviendo dependencias…"
# nos aseguramos de estar dentro de $INSTALL_DIR
cd "$INSTALL_DIR"
if ! [ -f go.mod ]; then
  go mod init "$MODULE_PATH"
fi
go mod tidy

log "Compilando binario…"
go build -o "$APP_BIN" .

# Permisos
chown -R "$APP_USER":"$APP_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR/$APP_BIN"

# 5) Env del servicio
log "Escribiendo archivo de entorno en $ENV_FILE…"
cat > "$ENV_FILE" <<EOF
# Variables de entorno para $SERVICE_NAME
PORT=$APP_PORT
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chmod 644 "$ENV_FILE"

# 6) Unidad systemd
log "Creando unidad systemd: /etc/systemd/system/$SERVICE_NAME"
cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Go WebApp (muestra hora e IP)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_DIR/$APP_BIN
Restart=on-failure
RestartSec=3

# Endurecimiento básico
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR
CapabilityBoundingSet=
LockPersonality=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

# 7) UFW (si procede)
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    log "Abriendo puerto $APP_PORT/TCP en UFW…"
    ufw allow "${APP_PORT}/tcp" || true
  fi
fi

# 8) Habilitar e iniciar servicio
log "Recargando systemd, habilitando e iniciando el servicio…"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 1
systemctl --no-pager --full status "$SERVICE_NAME" || true

echo
echo "=============================================="
echo " Despliegue completado"
echo "----------------------------------------------"
echo "Binario:           $INSTALL_DIR/$APP_BIN"
echo "Servicio:          $SERVICE_NAME"
echo "Entorno:           $ENV_FILE"
echo "Usuario servicio:  $APP_USER"
echo
echo "Comandos útiles:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo "  sudo systemctl restart $SERVICE_NAME"
echo
echo "Accede a:"
echo "  http://<ip_servidor>:$APP_PORT/"
echo "  http://<ip_servidor>:$APP_PORT/api"
echo "=============================================="
