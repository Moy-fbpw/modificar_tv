#!/bin/sh
# Mide qué tan cargada está la TV, para comparar antes y después de cada tanda. Solo lee, salvo que
# abre y cierra las apps que mide y, con --arranque o --despertar, reinicia o suspende la TV.
#
#   sh medir.sh <IP_TV> "antes"                        memoria, procesos y cuánto tardan en abrir las apps
#   sh medir.sh <IP_TV> "antes" --arranque             además reinicia y mide cuánto tarda en arrancar
#   sh medir.sh <IP_TV> "antes" --despertar            además la suspende y mide cuánto tarda en despertar
#   sh medir.sh <IP_TV> "antes" --protector            además prende el protector de pantalla y mide cuánto tarda en salir
#   sh medir.sh <IP_TV> "antes" --arranque --despertar las dos
#   APPS="com.netflix.ninja" sh medir.sh <IP_TV> "x"   mide otras apps (separadas por espacio)
#   DORMIR=600 sh medir.sh <IP_TV> "x" --despertar     la deja suspendida 10 minutos (por omisión, 60 s)
#   PROTECTOR=600 sh medir.sh <IP_TV> "x" --protector  deja el protector 10 minutos (por omisión, 60 s)
#
# Ojo: en algunas TV (como la Hisense 40A45H) la tecla de suspender apaga la TV por completo; ahí
# --despertar no se puede medir por adb y lo que importa es --arranque.
#
# Cada medición se agrega como una fila a mediciones.tsv, para compararlas en una tabla.
set -e
cd "$(dirname "$0")"

TARGET="$1"; LABEL="${2:-sin nombre}"; BOOT=; WAKE=; DREAM=
[ $# -gt 2 ] && shift 2 || set --
for a in "$@"; do case "$a" in --arranque) BOOT=1 ;; --despertar) WAKE=1 ;; --protector) DREAM=1 ;; *) echo "No entiendo: $a" >&2; exit 1 ;; esac; done
[ -n "$TARGET" ] || { echo "Uso: sh medir.sh <IP_TV> [\"etiqueta\"] [--arranque] [--despertar] [--protector]" >&2; exit 1; }
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

# La pantalla que abre una app desde Inicio. Las apps solo de TV (Crunchyroll, Prime Video) no tienen
# entrada de teléfono, así que primero se busca la de TV.
launch_comp() {
  comp=$(sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN \
    -c android.intent.category.LEANBACK_LAUNCHER "$1" | tail -1)
  case "$comp" in */*) ;; *) comp=$(sh_tv cmd package resolve-activity --brief "$1" | tail -1) ;; esac
  case "$comp" in */*) echo "$comp" ;; esac
}

# Apertura en frío: se cierra la app y se abre tres veces; se guarda la mediana en milisegundos.
open_ms() {
  comp=$(launch_comp "$1")
  [ -n "$comp" ] || { echo -; return; }
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
    echo "  Despertar: la TV se desconectó al suspenderse (o se apagó por completo), así que no se puede medir por adb." >&2
    echo "  Préndela con el control. En ese caso, lo que mide la espera es --arranque." >&2
  else
    t0=$(now_ms)
    sh_tv input keyevent KEYCODE_WAKEUP
    i=0; until awake; do i=$((i + 1)); [ $i -le 300 ] || break; done
    wake_ms=$(( $(now_ms) - t0 ))
    i=0; until online; do i=$((i + 1)); [ $i -le 60 ] || break; sleep 0.5; done
    online && net_ms=$(( $(now_ms) - t0 ))
    if [ -n "$first_app" ]; then
      comp=$(launch_comp "$first_app")
      sh_tv am start -W -n "$comp" >/dev/null
      wake_app_ms=$(( $(now_ms) - t0 ))
      sleep 3; sh_tv input keyevent KEYCODE_HOME
    fi
    echo "  Despertar (pantalla): $wake_ms ms"
    echo "  Internet tras despertar: $net_ms ms"
    [ -z "$first_app" ] || echo "  Despertar y abrir $first_app: $wake_app_ms ms"
  fi
fi

# Protector de pantalla: Android solo deja prenderlo a mano con root, así que se baja un momento el tiempo
# de espera (screen_off_timeout) para que se prenda solo, como en la vida real, y se regresa el valor
# original en cuanto arranca (o si el script se interrumpe). Pasado el tiempo, se presiona Inicio como con el
# control. Se mide hasta que el protector se quita, hasta que la pantalla de inicio tiene el foco y hasta
# que abre la primera app de la lista. Cada consulta por la red tarda unos 100-200 ms: es la precisión.
dream_ms=-; dream_home_ms=-; dream_app_ms=-
dreaming() { sh_tv dumpsys dreams 2>/dev/null | grep -m1 'mCurrentDream=' | grep -vq 'mCurrentDream=null'; }
if [ -n "$DREAM" ]; then
  PROTECTOR=${PROTECTOR:-60}
  home_pkg=$(sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1 | sed 's|/.*||')
  echo "Prendiendo el protector de pantalla $PROTECTOR s…"
  sh_tv input keyevent KEYCODE_HOME; sleep 3
  old_timeout=$(sh_tv settings get system screen_off_timeout)
  restore_timeout() { [ -z "$old_timeout" ] || sh_tv settings put system screen_off_timeout "$old_timeout"; old_timeout=; }
  trap restore_timeout EXIT INT TERM
  sh_tv settings put system screen_off_timeout 15000
  i=0; until dreaming; do i=$((i + 1)); [ $i -le 90 ] || break; sleep 1; done
  restore_timeout
  if ! dreaming; then
    echo "  Protector: no se prendió en 90 s, así que no se midió." >&2
  else
    sleep "$PROTECTOR"
    t0=$(now_ms)
    sh_tv input keyevent KEYCODE_HOME
    i=0; while dreaming; do i=$((i + 1)); [ $i -le 300 ] || break; done
    dream_ms=$(( $(now_ms) - t0 ))
    i=0; until sh_tv dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus=' | grep -q "$home_pkg"; do
      i=$((i + 1)); [ $i -le 300 ] || break; done
    dream_home_ms=$(( $(now_ms) - t0 ))
    if [ -n "$first_app" ]; then
      sh_tv am start -W -n "$(launch_comp "$first_app")" >/dev/null
      dream_app_ms=$(( $(now_ms) - t0 ))
      sleep 3; sh_tv input keyevent KEYCODE_HOME
    fi
    echo "  Salir del protector:   $dream_ms ms"
    echo "  Inicio tras protector: $dream_home_ms ms"
    [ -z "$first_app" ] || echo "  Protector y abrir $first_app: $dream_app_ms ms"
  fi
fi

OUT=mediciones.tsv
[ -f "$OUT" ] || printf 'fecha\tetiqueta\tmemoria_libre_mb\tmemoria_total_mb\tprocesos\tcarga\tapps_encendidas\tapps_al_arrancar\tarranque_s\tdespertar_ms\tinternet_tras_despertar_ms\tdespertar_y_abrir_ms\tsalir_protector_ms\tinicio_tras_protector_ms\tprotector_y_abrir_ms\tapertura_ms\n' > "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$LABEL" "$mem_free" "$mem_total" \
  "$procs" "$load" "$apps_on" "$apps_boot" "$boot_s" "$wake_ms" "$net_ms" "$wake_app_ms" \
  "$dream_ms" "$dream_home_ms" "$dream_app_ms" "${times% }" >> "$OUT"
echo "Guardado en $OUT."
