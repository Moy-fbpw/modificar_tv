#!/bin/sh
# Mide qué tan cargada está la TV, para comparar antes y después de cada tanda. Solo lee, salvo que
# abre y cierra las apps que mide y, con --arranque, reinicia la TV.
#
#   sh medir.sh <IP_TV> "antes"                    memoria, procesos y cuánto tardan en abrir las apps
#   sh medir.sh <IP_TV> "tanda 1" --arranque       además reinicia y mide cuánto tarda en arrancar
#   APPS="com.netflix.ninja" sh medir.sh <IP_TV> "x"   mide otras apps (separadas por espacio)
#
# Cada medición se agrega como una fila a mediciones.tsv, para compararlas en una tabla.
set -e
cd "$(dirname "$0")"

TARGET="$1"; LABEL="${2:-sin nombre}"; BOOT=
[ "$3" = --arranque ] && BOOT=1
[ -n "$TARGET" ] || { echo "Uso: sh medir.sh <IP_TV> [\"etiqueta\"] [--arranque]" >&2; exit 1; }
case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null || true ;; esac
[ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || { echo "No se puede conectar con $TV." >&2; exit 1; }

sh_tv() { adb -s "$TV" shell "$@" </dev/null | tr -d '\r'; }
booted() { [ "$(sh_tv getprop sys.boot_completed 2>/dev/null)" = 1 ]; }
APPS=${APPS:-"com.google.android.youtube.tv com.netflix.ninja"}

# Arranque: desde que se pide reiniciar hasta que Android dice que terminó. Incluye unos segundos de
# reconexión de adb, igual en todas las mediciones, así que sirve para comparar.
boot_s=-
if [ -n "$BOOT" ]; then
  echo "Reiniciando la TV para medir el arranque…"
  # boot_id cambia en cada arranque: así no se confunde la TV que todavía se está apagando con la que ya arrancó.
  old_boot=$(sh_tv cat /proc/sys/kernel/random/boot_id)
  start=$(date +%s)
  adb -s "$TV" reboot
  i=0; until [ "$(sh_tv cat /proc/sys/kernel/random/boot_id 2>/dev/null)" != "$old_boot" ] && booted; do
    i=$((i + 1)); [ $i -le 120 ] || { echo "La TV no terminó de arrancar en 10 minutos." >&2; exit 1; }
    case "$TV" in *:*) adb connect "$TV" >/dev/null 2>&1 || true ;; esac
    sleep 5
  done
  boot_s=$(( $(date +%s) - start ))
  # Al terminar el arranque Android sigue abriendo servicios; se espera a que se calme antes de medir memoria.
  echo "Arrancó en ${boot_s} s. Espero 60 s a que se calme…"
  sleep 60
fi

mem_total=$(sh_tv cat /proc/meminfo | awk '/^MemTotal/ { print int($2 / 1024) }')
mem_free=$(sh_tv cat /proc/meminfo | awk '/^MemAvailable/ { print int($2 / 1024) }')
procs=$(sh_tv ps -A | tail -n +2 | wc -l | tr -d ' ')
load=$(sh_tv cat /proc/loadavg | cut -d' ' -f1)
apps_on=$(sh_tv pm list packages -e | grep -c '^package:' || true)

# Apertura en frío: se cierra la app y se abre tres veces; se guarda la mediana en milisegundos.
open_ms() {
  comp=$(sh_tv cmd package resolve-activity --brief "$1" | tail -1)
  case "$comp" in */*) ;; *) echo -; return ;; esac
  for _ in 1 2 3; do
    sh_tv am force-stop "$1"
    sleep 2
    sh_tv am start -W -n "$comp" | awk -F': ' '/^TotalTime/ { print $2 }'
    sleep 3
    sh_tv input keyevent KEYCODE_HOME
    sleep 2
  done | sort -n | sed -n 2p
}

echo "Medición «${LABEL}» en $TV"
echo "  Memoria libre:     $mem_free MB de $mem_total MB"
echo "  Procesos:          $procs"
echo "  Carga (1 min):     $load"
echo "  Apps encendidas:   $apps_on"
[ "$boot_s" = - ] || echo "  Arranque:          $boot_s s"
times=""
for p in $APPS; do
  ms=$(open_ms "$p"); [ -n "$ms" ] || ms=-
  if [ "$ms" = - ]; then echo "  Abrir $p: no está instalada"
  else echo "  Abrir $p: $ms ms"; fi
  times="$times$p=$ms "
done

OUT=mediciones.tsv
[ -f "$OUT" ] || printf 'fecha\tetiqueta\tmemoria_libre_mb\tmemoria_total_mb\tprocesos\tcarga\tapps_encendidas\tarranque_s\tapertura_ms\n' > "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$LABEL" "$mem_free" "$mem_total" \
  "$procs" "$load" "$apps_on" "$boot_s" "${times% }" >> "$OUT"
echo "Guardado en $OUT."
