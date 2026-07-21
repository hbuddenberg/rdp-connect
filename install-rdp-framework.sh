#!/usr/bin/env bash
set -e

# Resolve repo-relative source paths so the installer works from any CWD.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Desplegando RDP Master Framework en el sistema..."

# 1. Crear directorios estándar (XDG Base Directory)
mkdir -p ~/.config/rdp/profiles
mkdir -p ~/.config/rdp/i18n
mkdir -p ~/.local/bin
mkdir -p ~/.local/lib/rdp
mkdir -p ~/.local/state/rdp
mkdir -p ~/Compartido

# 2. Diccionario de Idioma: Español (~/.config/rdp/i18n/es.env)
install -D -m 600 "$SCRIPT_DIR/i18n/es.env" ~/.config/rdp/i18n/es.env

# 3. Diccionario de Idioma: Inglés (~/.config/rdp/i18n/en.env)
install -D -m 600 "$SCRIPT_DIR/i18n/en.env" ~/.config/rdp/i18n/en.env

# 4. Plantilla Base para nuevos perfiles (~/.config/rdp/template.env)
install -D -m 600 "$SCRIPT_DIR/template/template.env" ~/.config/rdp/template.env

# 5. Perfil Preconfigurado: Partner (~/.config/rdp/profiles/partner.env)
# Se preservan los perfiles existentes del usuario (idempotente).
if [ ! -f ~/.config/rdp/profiles/partner.env ]; then
cat << 'PROFILE_PARTNER' > ~/.config/rdp/profiles/partner.env
HOST="hb-tipartner"
DOMAIN="MicrosoftAccount"
USER_RDP="h.buddenberg@tipartner.cl"
PASS_RDP="INGRESA_TU_PASSWORD_AQUI"
VPN_CHECK=""
PREFERRED_WS="3"
LANG_OVERRIDE="es"
PROFILE_PARTNER
fi

# 6. Biblioteca de funciones puras (~/.local/lib/rdp/rdp-common.bash)
#    Sourced por el motor y por el smoke test del instalador.
install -D -m 644 "$SCRIPT_DIR/lib/rdp-common.bash" ~/.local/lib/rdp/rdp-common.bash

# 7. Motor Maestro (~/.local/bin/rdp-connect)
install -D -m 700 "$SCRIPT_DIR/engine/rdp-connect" ~/.local/bin/rdp-connect

# 8. Restringir permisos de seguridad
chmod 700 ~/.local/bin/rdp-connect
chmod 700 ~/.config/rdp
chmod 700 ~/.config/rdp/profiles
chmod 600 ~/.config/rdp/template.env
chmod 600 ~/.config/rdp/profiles/*.env
chmod 600 ~/.config/rdp/i18n/*.env

echo "✅ Framework RDP desplegado exitosamente."
