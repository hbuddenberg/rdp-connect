#!/usr/bin/env bash
set -e

echo "🚀 Desplegando RDP Master Framework en el sistema..."

# 1. Crear directorios estándar (XDG Base Directory)
mkdir -p ~/.config/rdp/profiles
mkdir -p ~/.config/rdp/i18n
mkdir -p ~/.local/bin
mkdir -p ~/.local/state/rdp
mkdir -p ~/Compartido

# 2. Diccionario de Idioma: Español (~/.config/rdp/i18n/es.env)
cat << 'LANG_ES' > ~/.config/rdp/i18n/es.env
MSG_PROMPT_SELECT="Seleccionar RDP:"
MSG_ERR_NO_PROFILE="El perfil '%s' no existe."
MSG_ERR_VPN="VPN requerida (%s) inactiva."
MSG_ERR_HOST_UNREACHABLE="Servidor %s (3389) inalcanzable."
MSG_ALREADY_ACTIVE="Sesión activa. Enfocando ventana..."
MSG_SESSION_ENDED="Sesión finalizada."
MSG_CONNECTING="Conectando a %s (%s pantalla/s)..."
MSG_NEW_USAGE="Uso: rdp-connect --new <nombre_perfil>"
MSG_LOG_USAGE="Uso: rdp-connect --log <nombre_perfil>"
MSG_LOG_NO_FILE="No se encontró archivo de log para '%s'."
MSG_NEW_EXISTS="El perfil '%s' ya existe."
MSG_NEW_CREATED="Perfil creado en: %s"
MSG_NEW_OPENING="Abriendo editor con %s..."
MSG_NEW_NO_EDITOR="Edítalo manualmente en: %s"
LANG_ES

# 3. Diccionario de Idioma: Inglés (~/.config/rdp/i18n/en.env)
cat << 'LANG_EN' > ~/.config/rdp/i18n/en.env
MSG_PROMPT_SELECT="Select RDP:"
MSG_ERR_NO_PROFILE="Profile '%s' does not exist."
MSG_ERR_VPN="Required VPN (%s) is inactive."
MSG_ERR_HOST_UNREACHABLE="Server %s (3389) unreachable."
MSG_ALREADY_ACTIVE="Session active. Focusing window..."
MSG_SESSION_ENDED="Session ended."
MSG_CONNECTING="Connecting to %s (%s display/s)..."
MSG_NEW_USAGE="Usage: rdp-connect --new <profile_name>"
MSG_LOG_USAGE="Usage: rdp-connect --log <profile_name>"
MSG_LOG_NO_FILE="No log file found for '%s'."
MSG_NEW_EXISTS="Profile '%s' already exists."
MSG_NEW_CREATED="Profile created at: %s"
MSG_NEW_OPENING="Opening editor with %s..."
MSG_NEW_NO_EDITOR="Edit manually at: %s"
LANG_EN

# 4. Plantilla Base para nuevos perfiles (~/.config/rdp/template.env)
cat << 'TEMPLATE' > ~/.config/rdp/template.env
HOST="192.168.1.100"
DOMAIN="MicrosoftAccount" # Opciones: "MicrosoftAccount", "AzureAD", ""
USER_RDP="usuario@dominio.cl"
PASS_RDP="tu_contraseña_aqui"
VPN_CHECK=""             # IP/Host a verificar (ej: "10.8.0.1"), dejar vacío si no requiere
PREFERRED_WS="3"         # Workspace objetivo en Hyprland
LANG_OVERRIDE=""         # Forzar idioma (ej: "en", "es"), dejar vacío para autodetección
TEMPLATE

# 5. Perfil Preconfigurado: Partner (~/.config/rdp/profiles/partner.env)
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

# 6. Motor Maestro (~/.local/bin/rdp-connect)
cat << 'ENGINE' > ~/.local/bin/rdp-connect
#!/usr/bin/env bash

# Capturar errores reales dentro de pipelines
set -o pipefail

PROFILES_DIR="$HOME/.config/rdp/profiles"
I18N_DIR="$HOME/.config/rdp/i18n"
LOG_DIR="$HOME/.local/state/rdp"
SHARE_DIR="$HOME/Compartido"

mkdir -p "$LOG_DIR" "$SHARE_DIR"

# --- DETECCIÓN Y CARGA DE IDIOMA (i18n) ---
load_language() {
    local target_lang="${1:-${LANG:0:2}}"
    local lang_file="$I18N_DIR/${target_lang}.env"
    [ -f "$lang_file" ] && source "$lang_file" || source "$I18N_DIR/es.env"
}
load_language

# --- PARSER SEGURO DE CONFIGURACIÓN (Previene inyección de código Bash) ---
parse_env_safe() {
    local file="$1"
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # Sanitizar comillas iniciales y finales
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        printf -v "$key" "%s" "$value"
    done < "$file"
}

# --- MODO VISOR DE LOGS: rdp-connect --log <perfil> ---
if [ "$1" == "--log" ] || [ "$1" == "-l" ]; then
    LOG_PROFILE="$2"
    [ -z "$LOG_PROFILE" ] && { echo "$MSG_LOG_USAGE"; exit 1; }
    TARGET_LOG="$LOG_DIR/${LOG_PROFILE}.log"
    [ ! -f "$TARGET_LOG" ] && { printf "$MSG_LOG_NO_FILE\n" "$LOG_PROFILE"; exit 1; }
    echo "=== Viendo log en vivo de '$LOG_PROFILE' ($TARGET_LOG) ==="
    tail -n 30 -f "$TARGET_LOG"
    exit 0
fi

# --- MODO CREADOR: rdp-connect --new <perfil> ---
if [ "$1" == "--new" ]; then
    NEW_PROFILE="$2"
    [ -z "$NEW_PROFILE" ] && { echo "$MSG_NEW_USAGE"; exit 1; }

    TARGET_FILE="$PROFILES_DIR/${NEW_PROFILE}.env"
    [ -f "$TARGET_FILE" ] && { printf "$MSG_NEW_EXISTS\n" "$NEW_PROFILE"; exit 1; }

    cp "$HOME/.config/rdp/template.env" "$TARGET_FILE"
    chmod 600 "$TARGET_FILE"
    printf "$MSG_NEW_CREATED\n" "$TARGET_FILE"

    SYSTEM_EDITOR="${EDITOR:-${VISUAL}}"
    if [ -z "$SYSTEM_EDITOR" ]; then
        for ed in nvim vim nano vi micro; do
            if command -v "$ed" &>/dev/null; then
                SYSTEM_EDITOR="$ed"
                break
            fi
        done
    fi

    # Si se invoca desde GUI sin TTY, lanzar dentro de emulador de terminal
    if [ ! -t 0 ]; then
        TERM_EMU="${TERMINAL:-kitty}"
        $TERM_EMU -e "$SYSTEM_EDITOR" "$TARGET_FILE" &
    else
        "$SYSTEM_EDITOR" "$TARGET_FILE"
    fi
    exit 0
fi

# --- MODO SELECTOR (Wofi / Rofi) ---
PROFILE="$1"
if [ -z "$PROFILE" ]; then
    if command -v wofi &>/dev/null; then
        PROFILE=$(ls "$PROFILES_DIR" | sed 's/\.env$//' | wofi --dmenu --prompt "$MSG_PROMPT_SELECT")
    elif command -v rofi &>/dev/null; then
        PROFILE=$(ls "$PROFILES_DIR" | sed 's/\.env$//' | rofi -dmenu -p "$MSG_PROMPT_SELECT")
    fi
fi
[ -z "$PROFILE" ] && exit 0

ENV_FILE="$PROFILES_DIR/${PROFILE}.env"
[ ! -f "$ENV_FILE" ] && { notify-send -u critical "RDP Error" "$(printf "$MSG_ERR_NO_PROFILE" "$PROFILE")"; exit 1; }

# Carga segura de variables
parse_env_safe "$ENV_FILE"
[ -n "$LANG_OVERRIDE" ] && load_language "$LANG_OVERRIDE"

WM_CLASS="rdp-${PROFILE}"
LOG_FILE="$LOG_DIR/${PROFILE}.log"
PID_FILE="/tmp/rdp-${PROFILE}.pid"
START_TIME=$(date +%s)

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

# --- SINGLE INSTANCE GUARD (Flock exclusivo por perfil) ---
exec 200>"$PID_FILE"
if ! flock -n 200; then
    log_event "WARN" "Instancia activa detectada mediante PID lock. Enfocando ventana..."
    notify-send -i display "RDP $PROFILE" "$MSG_ALREADY_ACTIVE"
    hyprctl dispatch focuswindow "class:^($WM_CLASS)$"
    exit 0
fi

# --- CLEANUP TRAP & DIAGNÓSTICO ---
cleanup() {
    EXIT_CODE=$?
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ $EXIT_CODE -ne 0 ]; then
        LAST_ERROR=$(tail -n 15 "$LOG_FILE" | grep -iE "error|failed|status|connect" | tail -n 1)
        log_event "ERROR" "Sesión finalizada con error (Código $EXIT_CODE). Duración: ${DURATION}s."
        log_event "ERROR" "Causa reportada: ${LAST_ERROR:-Error no especificado}"
        notify-send -u critical -i network-error "RDP $PROFILE Error" "${LAST_ERROR:-Ver log en $LOG_FILE}"
    else
        log_event "INFO" "Sesión finalizada correctamente. Duración total: ${DURATION}s."
        notify-send -i display-off "RDP $PROFILE" "$MSG_SESSION_ENDED"
    fi
    rm -f "$PID_FILE"
}
trap cleanup EXIT

log_event "INFO" "=================== INICIO DE SESIÓN RDP ==================="
log_event "INFO" "Perfil: $PROFILE | Host: $HOST | Usuario: $USER_RDP"

# --- PRE-FLIGHT CHECK (Vía socket nativo /dev/tcp) ---
if [ -n "$VPN_CHECK" ]; then
    log_event "INFO" "Verificando VPN ($VPN_CHECK)..."
    if ! timeout 2 bash -c "</dev/tcp/$VPN_CHECK/3389" &>/dev/null; then
        ERR_VPN=$(printf "$MSG_ERR_VPN" "$VPN_CHECK")
        log_event "ERROR" "VPN requerida ($VPN_CHECK) inalcanzable. Abortando."
        notify-send -u critical -i network-vpn "RDP Error" "$ERR_VPN"
        exit 1
    fi
fi

log_event "INFO" "Verificando disponibilidad de puerto 3389 en $HOST..."
if ! timeout 2 bash -c "</dev/tcp/$HOST/3389" &>/dev/null; then
    ERR_HOST=$(printf "$MSG_ERR_HOST_UNREACHABLE" "$HOST")
    log_event "ERROR" "Servidor $HOST:3389 inalcanzable. Abortando."
    notify-send -u critical -i network-error "RDP Error" "$ERR_HOST"
    exit 1
fi
log_event "INFO" "Puerto 3389 en $HOST respondiendo correctamente."

# --- HIDPI AUTO-SCALING ---
SCALE=$(hyprctl monitors -j | jq -r '.[0].scale // 1.0')
DPI_FLAGS=""
if (( $(echo "$SCALE > 1.0" | bc -l 2>/dev/null || echo "0") )); then
    SCALE_PCT=$(python3 -c "print(int($SCALE * 100))" 2>/dev/null || echo "100")
    DPI_FLAGS="/scale-desktop:$SCALE_PCT /smart-sizing"
    log_event "INFO" "Escalado HiDPI detectado ($SCALE). Aplicando /scale-desktop:$SCALE_PCT."
fi

# --- MULTI-MONITOR Y REGLAS DE HYPRLAND ---
MONITORS=$(hyprctl monitors -j | jq -r '.[].id' | paste -sd, -)
MON_COUNT=$(hyprctl monitors -j | jq '. | length')
MON_FLAGS=$([ "$MON_COUNT" -gt 1 ] && echo "/multimon /monitors:$MONITORS" || echo "/f")

log_event "INFO" "Pantallas detectadas en Hyprland: $MON_COUNT (IDs: $MONITORS)."

if [ -n "$PREFERRED_WS" ]; then
    hyprctl keyword windowrulev2 "workspace $PREFERRED_WS, class:^($WM_CLASS)$" &>/dev/null
    log_event "INFO" "Asignando ventana $WM_CLASS al Workspace $PREFERRED_WS."
fi

export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export LIBVA_DRIVER_NAME=iHD

notify-send -i display "RDP Framework" "$(printf "$MSG_CONNECTING" "$PROFILE" "$MON_COUNT")"

log_event "INFO" "Lanzando xfreerdp3 mediante STDIN seguro..."

# --- EJECUCIÓN (Contraseña oculta de la tabla de procesos ps aux) ---
echo "$PASS_RDP" | xfreerdp3 \
  /v:"$HOST" \
  ${DOMAIN:+/d:"$DOMAIN"} \
  /u:"$USER_RDP" \
  /from-stdin:force \
  /wm-class:"$WM_CLASS" \
  /sec:nla \
  /cert:tofu \
  $MON_FLAGS \
  $DPI_FLAGS \
  +grab-keyboard \
  /async-input \
  /async-update \
  /async-transport \
  /mouse-motion \
  /sound:sys:pipewire,latency:20 \
  /microphone:sys:pipewire \
  /camera \
  +clipboard \
  +smartcard \
  +printer \
  /drive:compartido,"$SHARE_DIR" \
  /network:auto \
  /gfx:avc444 \
  +fonts \
  +aero \
  +auto-reconnect \
  /reconnect-max-retries:10 2>&1 | while IFS= read -r line; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RDP] $line" >> "$LOG_FILE"
done
ENGINE

# 7. Restringir permisos de seguridad
chmod 700 ~/.local/bin/rdp-connect
chmod 700 ~/.config/rdp
chmod 700 ~/.config/rdp/profiles
chmod 600 ~/.config/rdp/template.env
chmod 600 ~/.config/rdp/profiles/*.env
chmod 600 ~/.config/rdp/i18n/*.env

echo "✅ Framework RDP desplegado exitosamente."
