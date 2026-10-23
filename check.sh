#!/bin/sh
# Revisa que la TV siga limpia y, con --fix, regresa lo que una actualización deshizo.
#
#   sh check.sh <IP_TV>                   revisa la pantalla de inicio
#   sh check.sh <IP_TV> --fix             y la corrige
#   sh check.sh <IP_TV> --fix mi-tv.txt   también revisa tu propia lista de cambios
#
# La lista tiene un cambio por línea (# inicia un comentario):
#   apagar com.ejemplo.app                     la app se queda apagada (también acepta «off»)
#   global window_animation_scale 0            un ajuste (global, secure o system)
#   device_config activity_manager max_cached_processes 4
set -e

TARGET="$1"; FIX=; LIST=
shift 2>/dev/null || true
for a in "$@"; do case "$a" in --fix) FIX=1 ;; *) LIST=$a ;; esac; done
[ -n "$TARGET" ] || { echo "Uso: sh check.sh <IP_TV> [--fix] [lista.txt]" >&2; exit 1; }
[ -z "$LIST" ] || { [ -f "$LIST" ] && [ -r "$LIST" ]; } || { echo "No se puede leer $LIST." >&2; exit 2; }
case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null || true ;; esac
[ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || { echo "No se puede conectar con $TV." >&2; exit 2; }

sh_tv() { adb -s "$TV" shell "$@" </dev/null | tr -d '\r'; } # si no, adb se comería la lista de abajo
bad=0
# Imprime una línea de resultado. Con --fix, aplica la corrección y vuelve a revisar.
check() { # nombre, comando de prueba, comando de corrección
  if eval "$2"; then echo "  bien      $1"; return; fi
  if [ -n "$FIX" ] && eval "$3" >/dev/null 2>&1 && eval "$2"; then echo "  corregido $1"; return; fi
  echo "  MAL       $1"; bad=$((bad + 1))
}
is_off() { sh_tv pm list packages -d "$1" | grep -qx "package:$1"; }
installed() { sh_tv pm list packages "$1" | grep -qx "package:$1"; }

# shellcheck disable=SC2034 # ME se lee dentro de las cadenas de check que pasan por eval
ME=com.ansub.tvhome/.MainActivity
home() { sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1; }
echo "Pantalla de inicio"
# Primero los launchers propios de la TV: mientras uno esté encendido, Inicio no se puede corregir.
# En el mismo argumento que cat: Git Bash en Windows convierte un argumento que empieza con / en ruta de Windows.
turned_off=$(sh_tv "cat /data/local/tmp/tvhome-disabled.txt" 2>/dev/null | sort -u)
for p in $turned_off; do
  check "$p sigue apagada" "is_off $p" "sh_tv pm disable-user --user 0 $p"
done
# En Google TV, install.sh deja encendida su pantalla de inicio salvo con GOOGLE_TV=1, así que es normal que Inicio la abra.
LAUNCHERX=com.google.android.apps.tv.launcherx
# Si solo se hizo la limpieza (o se ejecutó undo.sh), no hay pantalla de inicio que revisar.
if ! installed com.ansub.tvhome; then
  echo "  omitido   La pantalla de inicio nueva no está instalada"
elif [ "$(home)" != "$ME" ] && installed $LAUNCHERX && ! is_off $LAUNCHERX && ! echo "$turned_off" | grep -qx $LAUNCHERX; then
  echo "  bien      Inicio abre la pantalla de inicio de Google TV (se dejó encendida, como dijo install.sh; GOOGLE_TV=1 la apaga)"
else
  check "Inicio abre esta pantalla de inicio" '[ "$(home)" = "$ME" ]' \
    'sh_tv cmd role add-role-holder --user 0 android.app.role.HOME com.ansub.tvhome; sh_tv cmd package set-home-activity "$ME"'
fi

if [ -n "$LIST" ]; then
  echo "Tus cambios ($LIST)"
  grep -v '^[[:space:]]*#' "$LIST" | grep -v '^[[:space:]]*$' | while read -r kind a b c; do
    case "$kind" in
      off|apagar)
        if installed "$a"; then check "$a sigue apagada" "is_off $a" "sh_tv pm disable-user --user 0 $a"
        else echo "  no está  $a (no instalada)"; fi ;;
      global|secure|system)
        check "$kind $a = $b" "[ \"\$(sh_tv settings get $kind $a)\" = \"$b\" ]" "sh_tv settings put $kind $a $b" ;;
      device_config)
        check "$a/$b = $c" "[ \"\$(sh_tv device_config get $a $b)\" = \"$c\" ]" "sh_tv device_config put $a $b $c" ;;
      *) echo "  ?         no se entiende: $kind $a $b $c" ;;
    esac
  done > "${TMPDIR:-/tmp}/tvcheck.$$" || true
  cat "${TMPDIR:-/tmp}/tvcheck.$$"
  n=$(grep -c "  MAL  " "${TMPDIR:-/tmp}/tvcheck.$$" || true); bad=$((bad + n))
  rm -f "${TMPDIR:-/tmp}/tvcheck.$$"
fi

if [ "$bad" -gt 0 ]; then
  [ -n "$FIX" ] && echo "$bad cosa(s) no se pudieron corregir." || echo "$bad cosa(s) regresaron a como estaban. Ejecútalo otra vez con --fix para corregirlas."
  exit 1
fi
echo "Todo bien."
