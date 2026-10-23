#!/bin/sh
# Instala la pantalla de inicio en la TV y la deja como predeterminada. Solo necesita adb.
#
#   sh install.sh <IP_TV>                          elige tus apps de TV por ti
#   sh install.sh <IP_TV> "com.netflix.ninja,com.google.android.youtube.tv"
#   sh install.sh <IP_TV> "" "bluetooth,sound,picture"   agrega accesos a ajustes junto al reloj
#
# En Google TV (Chromecast con Google TV y otros) se deja encendida la pantalla de inicio de la TV.
# GOOGLE_TV=1 la apaga de todos modos; hazlo solo si puedes reconectarte por USB o por el puerto 5555.
#
# Instala out/tvhome.apk, que se compila con build.sh. No descarga nada de internet.
set -e
cd "$(dirname "$0")"

TARGET="$1"; APPS="$2"; QUICK="$3"
[ -n "$TARGET" ] || { echo "Uso: sh install.sh <IP_TV> [\"app1,app2,...\"] [\"bluetooth,sound,picture\"]" >&2; exit 1; }
command -v adb >/dev/null 2>&1 || {
  echo "Falta adb. Instálalo primero:" >&2
  echo "  Mac:     brew install android-platform-tools" >&2
  echo "  Windows: https://developer.android.com/tools/releases/platform-tools" >&2
  exit 1; }

# A una IP se le agrega :5555; un serial de adb (como emulator-5554) se usa tal cual.
case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null || true ;; esac

state=$(adb -s "$TV" get-state 2>&1 || true)
case "$state" in
  device) ;;
  *unauthorized*) echo "La TV está preguntando «¿Permitir depuración?». Elige Permitir (marca «Permitir siempre») y vuelve a ejecutar esto." >&2; exit 1 ;;
  *) echo "No se puede conectar con $TV. Revisa que la TV esté encendida, en la misma red Wi-Fi y con la depuración por USB o por red activada." >&2; exit 1 ;;
esac

APK=out/tvhome.apk
[ -f "$APK" ] || { echo "No existe $APK. Compílalo primero con: sh build.sh" >&2; exit 1; }

echo "Instalando… Si la TV muestra un aviso de Google Play Protect, síguelo en la TV para permitir la instalación."
if ! out=$(adb -s "$TV" install -r "$APK" 2>&1); then
  case "$out" in
    *UPDATE_INCOMPATIBLE*) echo "Reemplazando una copia anterior firmada con otra llave…"
                           adb -s "$TV" uninstall com.ansub.tvhome >/dev/null; adb -s "$TV" install "$APK" ;;
    *) echo "$out" >&2; exit 1 ;;
  esac
fi

if [ -n "$APPS" ] || [ -n "$QUICK" ]; then
  # La marca hace que la app aplique esta lista una sola vez, aunque Android repita este arranque después.
  set -- --es stamp "$(date +%s)"
  [ -n "$APPS" ] && set -- "$@" --es apps "\"$APPS\""
  [ -n "$QUICK" ] && set -- "$@" --es quick "\"$QUICK\""
  adb -s "$TV" shell am start -n com.ansub.tvhome/.MainActivity "$@" >/dev/null
fi

ME=com.ansub.tvhome/.MainActivity
# Conserva el código de salida de adb, así un comando que falla en la TV cuenta como fallido aquí.
sh_tv() { _rc=0; _out=$(adb -s "$TV" shell "$@") || _rc=$?; [ -z "$_out" ] || printf '%s\n' "$_out" | tr -d '\r'; return $_rc; }
current_home() { sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1; }

# La deja como inicio predeterminado: con el rol (Android 10+) y a la manera clásica.
if [ "$(sh_tv getprop ro.build.version.sdk)" -ge 29 ]; then
  sh_tv cmd role add-role-holder --user 0 android.app.role.HOME com.ansub.tvhome >/dev/null 2>&1 || true
fi
sh_tv cmd package set-home-activity "$ME" >/dev/null 2>&1 || true

# Pantallas de inicio conocidas que se pueden apagar sin riesgo.
LAUNCHERS="com.google.android.tvlauncher com.google.android.apps.tv.launcherx com.google.android.leanbacklauncher
  com.mitv.tvhome com.amazon.tv.launcher"

# Solo se apagan launchers conocidos. Ajustes, la configuración inicial y la interfaz del sistema
# también responden a Inicio y la TV los necesita para arrancar, así que esos, las apps desconocidas
# y todo lo que corre siempre se quedan encendidos.
is_launcher() {
  case "$1" in
    com.ansub.tvhome|com.android.settings|com.android.tv.settings|com.android.systemui|com.android.provision) return 1 ;;
    *setup*|*wraith*|*provision*|*systemui*|*tvcenter*|*.tv.framework*|*.tvinput*) return 1 ;;
  esac
  case " $(echo $LAUNCHERS) " in *" $1 "*) ;; *) return 1 ;; esac
  # Si no se pueden leer sus banderas, o corre siempre, se deja encendida.
  flags=$(sh_tv dumpsys package "$1" 2>/dev/null | sed -n '/pkgFlags=\[/{p;q;}')
  [ -n "$flags" ] || return 1
  case "$flags" in *PERSISTENT*) return 1 ;; esac
  return 0
}

is_off() { sh_tv pm list packages -d "$1" | grep -Fqx "package:$1"; }

# Apaga apps (no las desinstala). Cada una se anota primero en la TV, para que undo.sh siempre
# pueda volver a encenderla. Si no se puede anotar, se deja encendida.
turn_off() {
  for p in "$@"; do
    if ! sh_tv "echo $p >> /data/local/tmp/tvhome-disabled.txt"; then
      echo "Dejo $p encendida: no se pudo anotar para undo.sh." >&2; continue
    fi
    sh_tv pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
    if is_off "$p"; then turned_off="$turned_off $p"; else echo "No se pudo apagar $p." >&2; fi
  done
  # Android guarda esto unos segundos después. Reiniciar antes puede deshacerlo.
  echo "Guardando el cambio en la TV, tarda 15 segundos…"
  sleep 15
  sh_tv cmd package set-home-activity "$ME" >/dev/null 2>&1 || true
}

# La app de configuración inicial de Google TV. Se trata aparte más abajo.
WRAITH=com.google.android.tungsten.setupwraith
LAUNCHERX=com.google.android.apps.tv.launcherx
turned_off=""

# Google TV (Chromecast con Google TV y muchas TVs nuevas): apagar su pantalla de inicio ha dejado
# algunas reiniciándose sin parar, y por Depuración inalámbrica la conexión puede caerse antes de
# poder regresar nada. Por eso en Google TV no se apaga nada salvo que lo pidas con GOOGLE_TV=1.
installed() { sh_tv pm list packages "$1" 2>/dev/null | grep -Fqx "package:$1"; }
google_tv=
# La pantalla de inicio propia de Google TV es lo que la hace Google TV. Android TV también tiene la app de configuración.
if installed "$LAUNCHERX"; then google_tv=1; fi
may_turn_off=1
if [ -n "$google_tv" ] && [ "$GOOGLE_TV" != 1 ]; then
  may_turn_off=
  if [ "$(current_home)" != "$ME" ]; then
    echo "Esta TV es Google TV, así que su pantalla de inicio se queda encendida."
    echo "Apagarla ha dejado algunas Google TV (como Chromecast) reiniciándose sin parar."
    echo "La nueva pantalla de inicio quedó instalada, pero Inicio sigue abriendo la de Google TV. La limpieza funciona igual."
    echo "Solo si puedes reconectarte a esta TV por USB o por el puerto 5555, vuelve a ejecutarlo con GOOGLE_TV=1."
  fi
fi
home_apps() { sh_tv cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
  | grep / | sed 's|/.*||; s/^ *//' | sort -u; }

# En la mayoría de las TVs, su launcher propio sigue ganando al presionar Inicio. La solución es apagarlo.
if [ -n "$may_turn_off" ] && [ "$(current_home)" != "$ME" ]; then
  others=""
  for p in $(home_apps); do
    if is_launcher "$p"; then others="$others $p"; continue; fi
    case "$p" in com.ansub.tvhome|com.android.settings|com.android.tv.settings|"$WRAITH") ;; *) echo "Dejo $p encendida: la TV podría necesitarla para arrancar." ;; esac
  done
  others=$(echo $others | tr ' ' '\n')
  if [ -n "$others" ]; then
    echo "La pantalla de inicio de tu TV sigue tomando el control:"
    echo "$others" | sed 's/^/  /'
    answer=${YES:+s}
    if [ -z "$answer" ]; then
      printf "¿La apago para que Inicio abra tu nueva pantalla de inicio? Puedes deshacerlo con undo.sh. [s/N] "
      read answer </dev/tty || answer=n
    fi
    case "$answer" in
      s|S|si|sí|y|Y|yes) turn_off $others ;;
      *) echo "Se quedó encendida. Tu TV podría seguir abriendo su propia pantalla de inicio." ;;
    esac
  fi
fi

# En algunas Google TV (como Sony BRAVIA) la app de configuración gana Inicio cuando la pantalla de
# inicio de Google TV está apagada. Solo se ofrece si Inicio abre justo esa app, la pantalla de inicio
# de Google TV ya está apagada, la TV terminó su configuración inicial y el sistema no la mantiene
# siempre corriendo. YES=1 no la cubre: necesita su propia respuesta, o YES_SETUP=1.
off_list=$(sh_tv pm list packages -d "$LAUNCHERX" 2>/dev/null) || off_list=
if [ -n "$may_turn_off" ] && [ "$(current_home | sed 's|/.*||')" = "$WRAITH" ] \
    && printf '%s\n' "$off_list" | grep -Fqx "package:$LAUNCHERX"; then
  flags=$(sh_tv dumpsys package "$WRAITH" 2>/dev/null | sed -n '/pkgFlags=\[/{p;q;}')
  [ -n "$flags" ] || flags=PERSISTENT
  if [ "$(sh_tv settings get global device_provisioned)" != 1 ] || [ "$(sh_tv settings get secure user_setup_complete)" != 1 ]; then
    echo "Dejo $WRAITH encendida: tu TV no ha terminado su configuración inicial."
  else case "$flags" in
    *PERSISTENT*) echo "Dejo $WRAITH encendida: la TV podría necesitarla para arrancar." ;;
    *)
      echo "La app de configuración de Google TV ($WRAITH) está tomando el control de Inicio."
      echo "Apagarla lo resolvió en una Sony BRAVIA, pero no se ha probado en todas las TVs."
      echo "Si algo sale mal, undo.sh la vuelve a encender."
      if [ "$YES_SETUP" = 1 ]; then answer=s
      elif [ -n "$YES" ]; then answer=n
      else
        printf "¿Apago también la app de configuración? [s/N] "
        read answer </dev/tty || answer=n
      fi
      case "$answer" in
        s|S|si|sí|y|Y|yes) turn_off "$WRAITH" ;;
        *) echo "Se quedó encendida. Tu TV podría seguir abriendo su app de configuración al presionar Inicio. Para apagarla después, vuelve a ejecutar esto con YES_SETUP=1." ;;
      esac ;;
  esac; fi
fi

# Si Inicio todavía no nos abre, lo que se apagó solo dejó a la TV sin pantalla de inicio. En Google
# TV la pantalla de recuperación de la app de configuración se reinicia sin parar, y tras reiniciar
# algunas TVs nunca pasan del logo (#14, #16). Por eso se vuelve a encender todo antes de salir.
reverted=
winner=$(current_home)
# Ninguna respuesta significa que la TV se desconectó (por Depuración inalámbrica la conexión puede caerse
# cuando se apaga la app de configuración), no que Inicio abra otra cosa. Se dice eso, en vez de un Inicio sin revisar.
[ -n "$winner" ] || [ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || {
  echo "Se perdió la conexión con $TV antes de poder revisar que Inicio abra esta pantalla de inicio." >&2
  echo "Reconéctate por USB o por el puerto 5555 y vuelve a ejecutar install.sh. Si la TV se quedó trabada, undo.sh vuelve a encender todo." >&2
  exit 1; }
if [ -n "$turned_off" ] && [ "$winner" != "$ME" ]; then
  revert_failed=
  for p in $turned_off; do
    sh_tv pm enable "$p" >/dev/null 2>&1 || true
    # Solo se olvida una app cuando la TV confirma que está encendida. Si adb falla, se queda en la lista de undo.sh.
    if ! state=$(sh_tv pm list packages -d "$p" 2>/dev/null); then
      echo "No se pudo revisar que $p esté encendida otra vez. Ejecuta undo.sh." >&2; revert_failed=1; continue
    elif printf '%s\n' "$state" | grep -Fqx "package:$p"; then
      echo "No se pudo volver a encender $p. Ejecuta undo.sh." >&2; revert_failed=1; continue
    fi
    sh_tv "sed -i '/^$p\$/d' /data/local/tmp/tvhome-disabled.txt" \
      || echo "No se pudo actualizar la lista de undo.sh para $p. undo.sh solo la volverá a encender." >&2
    # La pantalla de inicio de Google TV puede regresar sin su acceso a notificaciones (#16).
    [ "$p" = "$LAUNCHERX" ] && sh_tv cmd notification allow_listener \
      "$LAUNCHERX/.coreservices.notificationlistener.TvNotificationListenerService" >/dev/null 2>&1 || true
  done
  reverted=1
  if [ -n "$revert_failed" ]; then
    echo "Inicio abrió $winner en vez de esta pantalla de inicio. Algunas apps no se pudieron volver a encender: ejecuta undo.sh."
  else
    echo "Inicio abrió $winner en vez de esta pantalla de inicio, así que lo que se apagó ya está encendido otra vez."
  fi
fi

adb -s "$TV" shell input keyevent KEYCODE_HOME
if [ "$(current_home)" = "$ME" ]; then
  echo "Listo. Presiona Inicio en tu control remoto para verla."
elif [ -n "$reverted" ]; then
  echo "Quedó instalada, pero al presionar Inicio todavía se abre la pantalla de inicio de tu TV."
else
  echo "Quedó instalada, pero tu TV todavía abre su propia pantalla de inicio. Si pregunta qué pantalla de inicio usar, elige «Home» y luego Siempre."
fi
