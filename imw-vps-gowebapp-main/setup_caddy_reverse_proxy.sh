#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Ejecuta como root: sudo bash $0 <dominio> <puerto> <email> [--staging]"
  exit 1
fi

DOMAIN="${1:-}"
UPSTREAM_PORT="${2:-}"
EMAIL="${3:-}"
STAGING="${4:-}"

if [[ -z "$DOMAIN" || -z "$UPSTREAM_PORT" || -z "$EMAIL" ]]; then
  echo "Uso: $0 <dominio> <puerto_upstream> <email_contacto> [--staging]"
  echo "Ej : $0 midominio.com 8080 admin@midominio.com"
  exit 1
fi
if ! [[ "$UPSTREAM_PORT" =~ ^[0-9]+$ ]] || (( UPSTREAM_PORT < 1 || UPSTREAM_PORT > 65535 )); then
  echo "[ERROR] Puerto inválido: $UPSTREAM_PORT"; exit 1
fi

echo "[INFO] Instalando Caddy (repo oficial)…"
apt update
apt install -y caddy

# UFW si está activo
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
fi

# Caddyfile
CADDYFILE="/etc/caddy/Caddyfile"
ACME_CA=""  # producción por defecto
if [[ "${STAGING:-}" == "--staging" ]]; then
  ACME_CA='{
    acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
  }'
fi

cat > "$CADDYFILE" <<EOF
# Caddyfile generado automáticamente

{
  email ${EMAIL}
  # logging global opcional:
  # log {
  #   output file /var/log/caddy/access.log
  #   level INFO
  # }
  ${ACME_CA}
}

${DOMAIN} {
  encode zstd gzip
  header {
    # Seguridad básica
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "strict-origin-when-cross-origin"
  }
  reverse_proxy 127.0.0.1:${UPSTREAM_PORT}
  # Si usas websockets o SSE, Caddy lo maneja automáticamente en reverse_proxy.
}
EOF

echo "[INFO] Probando y recargando configuración…"
caddy fmt --overwrite /etc/caddy/Caddyfile
caddy validate --config "$CADDYFILE"
systemctl enable caddy
systemctl reload caddy || systemctl restart caddy

echo
echo "[OK] Listo:"
echo " - Dominio:     https://${DOMAIN}"
echo " - Upstream:    http://127.0.0.1:${UPSTREAM_PORT}"
echo " - Config:      ${CADDYFILE}"
echo " - Certs:       /var/lib/caddy/.local/share/caddy (manejados por Caddy)"
echo
echo "Comprobaciones:"
echo "  systemctl status caddy --no-pager"
echo "  journalctl -u caddy -f"
