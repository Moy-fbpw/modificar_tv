#!/bin/sh
# Mide qué tan cargada está la TV, para comparar antes y después de cada tanda. Solo lee, salvo que
# abre y cierra las apps que mide y, con --arranque o --despertar, reinicia o suspende la TV.
#
#   sh medir.sh <IP_TV> "antes"                        memoria, procesos y cuánto tardan en abrir las apps
#   sh medir.sh <IP_TV> "antes" --arranque             además reinicia y mide cuánto tarda en arrancar
#   sh medir.sh <IP_TV> "antes" --despertar            además la suspende y mide cuánto tarda en despertar
#   sh medir.sh <IP_TV> "antes" --arranque --despertar las dos
#   APPS="com.netflix.ninja" sh medir.sh <IP_TV> "x"   mide otras apps (separadas por espacio)
#   DORMIR=600 sh medir.sh <IP_TV> "x" --despertar     la deja suspendida 10 minutos (por omisión, 60 s)
#
# Cada medición se agrega como una fila a mediciones.tsv, para compararlas en una tabla.
set -e
cd "$(dirname "$0")"

TARGET="$1"; LABEL="${2:-sin nombre}"; BOOT=; WAKE=
[ $# -gt 2 ] && shift 2 || set --
for a in "$@"; do case "$a" in --arranque) BOOT=1 ;; --despertar) WAKE=1 ;; *) echo "No entiendo: $a" >&2; exit 1 ;; esac; done
[ -n "$TARGET" ] || { echo "Uso: sh medir.sh <IP_TV> [\"etiqueta\"] [--arranque] [--despertar]" >&2; exit 1; }
case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null || true ;; esac
[ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || { echo "No se puede conectar con $TV." >&2; exit 1; }

sh_tv() { adb -s "$TV" shell "$@" </dev/null | tr -d '\r'; }
booted() { [ "$(sh_tv getprop sys.boot_completed 2>/dev/null)" = 1 ]; }
awake() { sh_tv dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'; }
online() { sh_tv 'ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 && echo si' | grep -q si; }
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
connected() {
  case "$TV" in *:*) adb connect "$TV" >/dev/null 2>&1 || true ;; esac
  [ "$(adb -s "$TV" get-state 2>/dev/null)" = device ]
}
# Crunchyroll primero: es la que más se nota lenta. Las que no estén instaladas se saltan.
APPS=${APPS:-"com.crunchyroll.crunchyroid com.google.android.youtube.tv com.amazon.amazonvideo.livingroom com.disney.disneyplus"}

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
# Apps que Android despierta en cada arranque: entre más, más tarda en quedar lista la TV.
apps_boot=$(sh_tv cmd package query-receivers --brief -a android.intent.action.BOOT_COMPLETED \
  | grep / | sed 's|/.*||; s/^ *//' | sort -u | wc -l | tr -d ' ')

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
echo "  Memoria libre:         $mem_free MB de $mem_total MB"
echo "  Procesos:              $procs"
echo "  Carga (1 min):         $load"
echo "  Apps encendidas:       $apps_on"
echo "  Apps que arrancan solas: $apps_boot"
[ "$boot_s" = - ] || echo "  Arranque:              $boot_s s"
times=""; first_app=
for p in $APPS; do
  ms=$(open_ms "$p"); [ -n "$ms" ] || ms=-
  if [ "$ms" = - ]; then echo "  Abrir $p: no está instalada"
  else echo "  Abrir $p: $ms ms"; [ -n "$first_app" ] || first_app=$p; fi
  times="$times$p=$ms "
done

# Despertar: se suspende con la tecla de dormir, se espera y se despierta como lo haría el control.
# Se mide hasta que la pantalla está encendida, hasta que hay internet y hasta que abre la primera app
# de la lista, sin cerrarla antes: así es como se usa después de una suspensión.
wake_ms=-; net_ms=-; wake_app_ms=-
if [ -n "$WAKE" ]; then
  DORMIR=${DORMIR:-60}
  echo "Suspendiendo la TV $DORMIR s para medir el despertar…"
  sh_tv input keyevent KEYCODE_SLEEP
  i=0; while awake; do i=$((i + 1)); [ $i -le 30 ] || break; sleep 1; done
  sleep "$DORMIR"
  if ! connected; then
    echo "  Despertar: la TV cortó la conexión al suspenderse, así que no se puede medir por adb." >&2
    echo "  Despiértala con el control. Que corte la red al dormir ya explica parte de la espera al despertar." >&2
  else
    t0=$(now_ms)
    sh_tv input keyevent KEYCODE_WAKEUP
    i=0; until awake; do i=$((i + 1)); [ $i -le 300 ] || break; done
    wake_ms=$(( $(now_ms) - t0 ))
    i=0; until online; do i=$((i + 1)); [ $i -le 60 ] || break; sleep 0.5; done
    online && net_ms=$(( $(now_ms) - t0 ))
    if [ -n "$first_app" ]; then
      comp=$(sh_tv cmd package resolve-activity --brief "$first_app" | tail -1)
      sh_tv am start -W -n "$comp" >/dev/null
      wake_app_ms=$(( $(now_ms) - t0 ))
      sleep 3; sh_tv input keyevent KEYCODE_HOME
    fi
    echo "  Despertar (pantalla): $wake_ms ms"
    echo "  Internet tras despertar: $net_ms ms"
    [ -z "$first_app" ] || echo "  Despertar y abrir $first_app: $wake_app_ms ms"
  fi
fi

OUT=mediciones.tsv
[ -f "$OUT" ] || printf 'fecha\tetiqueta\tmemoria_libre_mb\tmemoria_total_mb\tprocesos\tcarga\tapps_encendidas\tapps_al_arrancar\tarranque_s\tdespertar_ms\tinternet_tras_despertar_ms\tdespertar_y_abrir_ms\tapertura_ms\n' > "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$LABEL" "$mem_free" "$mem_total" \
  "$procs" "$load" "$apps_on" "$apps_boot" "$boot_s" "$wake_ms" "$net_ms" "$wake_app_ms" "${times% }" >> "$OUT"
echo "Guardado en $OUT."
