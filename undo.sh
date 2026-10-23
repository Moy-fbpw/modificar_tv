#!/bin/sh
# Quita la pantalla de inicio y vuelve a encender la pantalla de inicio propia de la TV.
# Uso: sh undo.sh <IP_TV>
set -e
[ -n "$1" ] || { echo "Uso: sh undo.sh <IP_TV>" >&2; exit 1; }
case "$1" in
  *.*.*.*:*) TV=$1 ;;
  *.*.*.*)   TV=$1:5555 ;;
  *)         TV=$1 ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null || true ;; esac
[ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || { echo "No se puede conectar con $TV." >&2; exit 1; }

failed=
# 0: la app está apagada. 1: está encendida o no está instalada. 2: no se pudo consultar a la TV.
is_off() {
  out=$(adb -s "$TV" shell pm list packages -d "$1") || return 2
  out=$(printf '%s\n' "$out" | tr -d '\r' | grep -v '^$') || return 1
  # Cualquier cosa que no sea una línea de paquete es un mensaje de error, aunque pm diga que funcionó.
  printf '%s\n' "$out" | grep -qv '^package:' && return 2
  printf '%s\n' "$out" | grep -Fqx "package:$1" && return 0
  return 1
}
# Vuelve a encender una app y revisa que haya funcionado. Una app que ya no está instalada cuenta como hecha.
turn_on() {
  adb -s "$TV" shell pm enable "$1" >/dev/null 2>&1 || true
  rc=0; is_off "$1" || rc=$?
  case $rc in
    1) echo "$1 encendida otra vez"
       # La pantalla de inicio de Google TV puede regresar sin su acceso a notificaciones (#16).
       [ "$1" = com.google.android.apps.tv.launcherx ] && adb -s "$TV" shell cmd notification allow_listener \
         com.google.android.apps.tv.launcherx/.coreservices.notificationlistener.TvNotificationListenerService >/dev/null 2>&1 || true ;;
    0) echo "No se pudo volver a encender $1." >&2; failed=1 ;;
    *) echo "No se pudo revisar que $1 esté encendida otra vez." >&2; failed=1 ;;
  esac
}

# Vuelve a encender lo que install.sh apagó, antes de quitar esta pantalla de inicio.
# END marca que se leyó completa; si no hay lista, también está bien.
LIST=/data/local/tmp/tvhome-disabled.txt
list=$(adb -s "$TV" shell "if [ -e $LIST ]; then cat $LIST && echo END; else echo END; fi" 2>/dev/null) || list=
list=$(printf '%s\n' "$list" | tr -d '\r')
case "$list" in
  *END) for p in $(printf '%s\n' "$list" | grep -vx END | sort -u); do turn_on "$p"; done ;;
  *) echo "No se pudo leer la lista de apps que apagó install.sh." >&2; failed=1 ;;
esac
# La app de configuración de Google TV pudo apagarse a mano, así que también se vuelve a encender.
W=com.google.android.tungsten.setupwraith
rc=0; is_off "$W" || rc=$?
case $rc in
  0) turn_on "$W" ;;
  1) ;;
  *) echo "No se pudo revisar $W." >&2; failed=1 ;;
esac

# Si algo se quedó apagado, se conservan esta pantalla de inicio y la lista, para que Inicio siga
# funcionando y undo.sh pueda intentarlo otra vez.
if [ -n "$failed" ]; then
  echo "Se conservó esta pantalla de inicio para que tu TV siga teniendo una. Ejecuta undo.sh otra vez, o enciende la app con: adb shell pm enable <paquete>" >&2
  exit 1
fi
# En el mismo argumento que rm, como la lectura de arriba: Git Bash en Windows convierte un argumento que empieza con / en ruta de Windows.
adb -s "$TV" shell "rm -f $LIST"
adb -s "$TV" uninstall com.ansub.tvhome >/dev/null 2>&1 || true
adb -s "$TV" shell input keyevent KEYCODE_HOME
echo "Listo. Tu TV regresó a su propia pantalla de inicio."
