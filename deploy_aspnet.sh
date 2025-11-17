#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Despliegue Automático de Aplicación ASP.NET Core (NET 8)
# =========================================================
#
# Requisitos:
# - Carpeta con el código fuente ASP.NET
# - Ejecutar este script desde la carpeta raíz del proyecto
#
# ---------- Config ----------
APP_NAME="miappaspnet"
SERVICE_NAME="miappaspnet.service"
INSTALL_DIR="/opt/$APP_NAME"
APP_USER="aspnetapp"
ENV_FILE="/etc/default/$APP_NAME"
PORT="5000"                         # Puerto ASP.NET Core
DLL_NAME="MiAppAspNet.dll"          # Cambia si tu DLL tiene otro nombre

log() { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
error() { printf "\n\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; }
require_root() { [[ $EUID -eq 0 ]] || { error "Ejecuta este script como root."; exit 1; }; }

require_root

# 1) Instalar .NET SDK si no existe
if ! command -v dotnet >/dev/null 2>&1; then
  log "Instalando .NET 8 SDK…"
  apt update
  apt install -y dotnet-sdk-8.0
fi

log "Versión de dotnet:"
dotnet --version

# 2) Crear usuario del servicio
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  log "Creando usuario del servicio: $APP_USER"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

# 3) Publicar la aplicación
log "Publicando aplicación en modo Release…"
dotnet publish -c Release -o publish_output

if ! [ -f "publish_output/$DLL_NAME" ]; then
  error "No se encontró el DLL publicado. Revisa DLL_NAME en el script."
  exit 1
fi

# 4) Copiar a /opt
log "Creando directorio de instalación: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r publish_output/* "$INSTALL_DIR"

chown -R "$APP_USER":"$APP_USER" "$INSTALL_DIR"
chmod -R 750 "$INSTALL_DIR"

# 5) Crear archivo de entorno
log "Creando archivo de entorno $ENV_FILE"
cat > "$ENV_FILE" <<EOF
ASPNETCORE_URLS=http://0.0.0.0:$PORT
ASPNETCORE_ENVIRONMENT=Production
EOF

chmod 644 "$ENV_FILE"

# 6) Crear servicio systemd
log "Creando servicio systemd: /etc/systemd/system/$SERVICE_NAME"
cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=ASP.NET Core WebApp ($APP_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/dotnet $INSTALL_DIR/$DLL_NAME
Restart=always
RestartSec=5

# Endurecimiento (Hardening)
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

# 7) Firewall opcional
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "Abriendo puerto $PORT en UFW…"
  ufw allow "$PORT"/tcp || true
fi

# 8) Activar servicio
log "Habilitando e iniciando servicio…"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 1

systemctl --no-pager --full status "$SERVICE_NAME" || true

echo
echo "=============================================="
echo "   DEPLOY COMPLETADO PARA $APP_NAME"
echo "----------------------------------------------"
echo "Directorio instalación: $INSTALL_DIR"
echo "Servicio systemd:       $SERVICE_NAME"
echo "Archivo entorno:        $ENV_FILE"
echo
echo "URL:"
echo "  http://<tu_servidor>:$PORT/"
echo
echo "Comandos útiles:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "=============================================="
