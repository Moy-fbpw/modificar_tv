#!/bin/sh
# Lista todas las apps de la TV con lo necesario para limpiarla sin riesgo. No cambia nada.
#
#   sh candidates.sh <IP_TV>
#
# Una línea por app, agrupadas por veredicto:
#
#   VEREDICTO  ESTADO  PAQUETE                            QUÉ ES
#
#   nunca      la TV la necesita, o Android la mantiene corriendo hagas lo que hagas. Déjala encendida.
#   conservar  trae una función (transmitir, buscar, TV en vivo). Apágala solo si no la usas.
#   seguro     relleno preinstalado común: anuncios, filas patrocinadas, apps de fábrica y de Google sin uso.
#   revisar    no se sabe nada de ella. Si tienes duda, déjala encendida.
#
# El estado es activa o apagada, para que lo que ya está apagado nunca se encienda por accidente.
#
# «nunca» también cubre las apps que Android marca como PERSISTENT: pm disable-user no se queda en
# esas, así que se vuelven a encender solas. Solo lee, se puede ejecutar cuando sea, igual en
# cualquier Android TV o Google TV. docs/debloat.md explica qué hacer con la lista.
set -e
cd "$(dirname "$0")" 2>/dev/null || true

TARGET="$1"
[ -n "$TARGET" ] || { echo "Uso: sh candidates.sh <IP_TV>" >&2; exit 1; }
command -v adb >/dev/null 2>&1 || {
  echo "Falta adb. Instala platform-tools primero:" >&2
  echo "  Mac:     brew install android-platform-tools" >&2
  echo "  Windows: https://developer.android.com/tools/releases/platform-tools" >&2
  exit 1; }

# A una IP se le agrega :5555; un serial de adb (como emulator-5554) se usa tal cual.
case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac
case "$TV" in *:*) adb connect "$TV" >/dev/null 2>&1 || true ;; esac
[ "$(adb -s "$TV" get-state 2>/dev/null)" = device ] || {
  echo "No se puede conectar con $TV. ¿La TV está encendida, en esta red y con la depuración permitida?" >&2; exit 1; }

sh_tv() { _rc=0; _out=$(adb -s "$TV" shell "$@" </dev/null 2>/dev/null) || _rc=$?; printf '%s\n' "$_out" | tr -d '\r'; return $_rc; }
# Si la TV se desconecta a la mitad, se detiene: una lista leída a medias daría veredictos equivocados.
lost() { echo "Se perdió la conexión con $TV mientras se leía la lista de apps. No se cambió nada. Vuelve a ejecutarlo." >&2; exit 1; }

# La TV las necesita para arrancar, o para seguir funcionando una vez encendida.
NEVER="com.google.android.gms com.google.android.gsf com.android.vending
com.android.tv.settings com.android.settings com.android.systemui
com.android.providers.settings com.android.settings.intelligence com.android.shell
com.android.packageinstaller com.google.android.packageinstaller
com.google.android.permissioncontroller com.android.bluetooth com.android.externalstorage
com.android.providers.media com.android.providers.media.module com.android.providers.downloads
com.android.keychain com.android.inputdevices com.android.location.fused com.android.se
com.android.providers.tv com.android.providers.contacts com.android.providers.calendar
com.android.networkstack.inprocess com.android.networkstack.permissionconfig
com.android.certinstaller com.android.companiondevicemanager com.android.dynsystem
com.android.statementservice com.android.vpndialogs com.android.wallpaperbackup
com.android.backupconfirm com.android.sharedstoragebackup com.android.localtransport
com.android.proxyhandler com.android.pacprocessor com.android.captiveportallogin
com.dolby.android.audio.service
com.google.android.inputmethod.latin com.android.inputmethod.latin com.google.android.leanback.ime
com.tcl.inputmethod.international com.android.providers.userdictionary
com.google.android.tungsten.setupwraith com.google.android.onetimeinitializer
com.google.android.partnersetup com.android.provision com.android.tv.provision com.android.managedprovisioning
com.tcl.suspension com.tcl.tvinput com.tcl.providers.config com.tcl.useragreement
com.tcl.settings com.tcl.tcl_bt_rcu_service com.google.android.apps.tv.launcherx"

# Apágalas solo si no usas la función que traen.
KEEP="com.google.android.apps.mediashell com.google.android.katniss
com.google.android.tv.assistant com.google.android.marvin.talkback
com.google.android.tv.remote.service com.google.android.tts
com.google.android.syncadapters.contacts com.google.android.syncadapters.calendar
com.ansub.tvhome com.google.android.webview com.tcl.android.webview
com.tcl.tv com.tcl.micmanager
com.android.dreams.basic com.google.android.apps.tv.dreamx"

# Relleno preinstalado común: anuncios, filas patrocinadas, apps de fábrica y de Google sin uso.
SAFE="com.google.android.tvrecommendations com.google.android.backdrop
com.google.android.videos com.google.android.youtube.tvmusic com.google.android.play.games
com.google.android.feedback
com.android.printspooler com.android.htmlviewer com.android.soundpicker
com.tcl.waterfall.overseas com.tcl.esticker com.tcl.partnercustomizer
com.tcl.messagebox com.tcl.smartalexa com.tcl.copydatatotv com.tcl.audioplayer
com.tcl.imageplayer com.tcl.keyhelp com.tcl.usercenter
com.tcl.dashboard com.tcl.ttvs com.tcl.micmanager com.tcl.factory.view"

dump=$(sh_tv dumpsys package) || lost
all=$(sh_tv pm list packages) || lost
off=$(sh_tv pm list packages -d) || lost
printf '%s\n' "$dump" | grep -q 'Package \[' || lost
printf '%s\n' "$all" | grep -q '^package:' || lost
all=$(printf '%s\n' "$all" | sed -n 's/^package://p')
off=$(printf '%s\n' "$off" | sed -n 's/^package://p')

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t tvcand)
trap 'rm -rf "$tmp"' EXIT

# Una sola llamada lee las banderas de todos los paquetes, así es rápido aun en una TV lenta.
printf '%s\n' "$dump" | awk '
  /^[[:space:]]*Package \[/ { n=$0; sub(/.*\[/,"",n); sub(/\].*/,"",n); cur=n; seen=0; next }
  cur!="" && !seen && /pkgFlags=\[/ { l=$0; sub(/.*pkgFlags=\[/,"",l); sub(/\].*/,"",l); print cur "\t" l; seen=1 }
' | sort -u > "$tmp/flags"

printf '%s\n' "$all" > "$tmp/all"
printf '%s\n' "$off" > "$tmp/off"

# Nombres en lenguaje normal, para que la lista se lea como una lista de apps y no de paquetes.
cat > "$tmp/names" <<'EOF'
com.google.android.gms	Servicios de Google Play
com.google.android.gsf	Framework de servicios de Google
com.android.vending	Google Play Store
com.android.tv.settings	Configuración de la TV
com.android.settings	Configuración
com.android.systemui	Interfaz del sistema
com.android.bluetooth	Bluetooth
com.google.android.apps.mediashell	Google Cast, transmitir desde el celular
com.google.android.katniss	Búsqueda y voz de Google TV
com.google.android.tv.assistant	Asistente de Google
com.google.android.marvin.talkback	Lector de pantalla TalkBack
com.google.android.tv.remote.service	Control remoto desde el celular
com.google.android.inputmethod.latin	Teclado Gboard
com.android.inputmethod.latin	Teclado de Android
com.google.android.tts	Texto a voz
com.google.android.tvrecommendations	Fila patrocinada de Google TV
com.google.android.backdrop	Anuncios de fondo de Google TV
com.google.android.videos	Google TV, Play Películas
com.google.android.youtube.tvmusic	YouTube Music
com.google.android.play.games	Play Juegos
com.google.android.youtube.tv	YouTube
com.google.android.feedback	Comentarios a Google
com.google.android.onetimeinitializer	Ayudante de configuración única
com.google.android.partnersetup	Configuración de apps de socios
com.google.android.syncadapters.contacts	Sincronización de contactos
com.google.android.syncadapters.calendar	Sincronización de calendario
com.android.printspooler	Impresión
com.android.dreams.basic	Protector de pantalla básico
com.google.android.apps.tv.dreamx	Protector de pantalla de Google TV
com.android.htmlviewer	Visor de archivos HTML
com.netflix.ninja	Netflix
com.amazon.amazonvideo.livingroom	Prime Video
com.tcl.waterfall.overseas	Contenido y anuncios de TCL
com.tcl.esticker	Etiqueta electrónica de TCL
com.tcl.partnercustomizer	Personalizador del launcher de TCL
com.tcl.suspension	Selector de entradas de TCL
com.tcl.messagebox	Buzón de mensajes de TCL
com.tcl.smartalexa	Alexa de TCL
com.tcl.copydatatotv	Migración desde el celular de TCL
com.tcl.audioplayer	Reproductor de audio de TCL
com.tcl.imageplayer	Visor de imágenes de TCL
com.tcl.videoplayer	Reproductor de video de TCL
com.tcl.keyhelp	Ayuda de botones de TCL
com.tcl.useragreement	Acuerdo de usuario de TCL
com.tcl.usercenter	Centro de usuario de TCL
com.tcl.dashboard	Panel de TCL
com.tcl.ttvs	Analítica y enlaces de Alexa de TCL
com.tcl.providers.config	Almacén de ajustes de TCL
com.tcl.settings	Ajustes de TCL
com.tcl.tvinput	Framework de entradas de TV
com.tcl.tv	TV en vivo
com.tcl.tcl_bt_rcu_service	Control remoto Bluetooth
com.google.android.tvlauncher	Pantalla de inicio de Google TV
com.google.android.apps.tv.launcherx	Pantalla de inicio de Google TV
com.google.android.leanbacklauncher	Pantalla de inicio de Android TV
com.google.android.tungsten.setupwraith	Configuración de Google TV
com.dolby.android.audio.service	Audio Dolby
com.ansub.tvhome	Pantalla de inicio nueva (este repo)
com.tcl.inputmethod.international	Teclado de la TV
com.google.android.webview	Páginas web dentro de las apps
com.tcl.android.webview	Páginas web dentro de las apps
com.google.android.apps.nbu.smartconnect.tv	Vinculación con el celular de Google TV
com.android.providers.userdictionary	Diccionario del teclado
EOF

# Una sola línea cada una: el awk que trae macOS no acepta saltos de línea dentro de -v.
NEVER=$(printf '%s' "$NEVER" | tr '\n' ' '); KEEP=$(printf '%s' "$KEEP" | tr '\n' ' '); SAFE=$(printf '%s' "$SAFE" | tr '\n' ' ')
awk -F'\t' -v never="$NEVER" -v keep="$KEEP" -v safe="$SAFE" -v tmp="$tmp" '
  BEGIN {
    n=split(never,x," "); for (i=1;i<=n;i++) if (x[i]!="") NV[x[i]]=1
    n=split(keep,x," ");  for (i=1;i<=n;i++) if (x[i]!="") KP[x[i]]=1
    n=split(safe,x," ");  for (i=1;i<=n;i++) if (x[i]!="") SF[x[i]]=1
    while ((getline l < (tmp "/flags")) > 0) { split(l,y,"\t"); FL[y[1]]=y[2] }
    while ((getline l < (tmp "/off")) > 0) OF[l]=1
    while ((getline l < (tmp "/names")) > 0) { split(l,y,"\t"); NM[y[1]]=y[2] }
    ORD["nunca"]=0; ORD["conservar"]=1; ORD["seguro"]=2; ORD["revisar"]=3
    while ((getline l < (tmp "/all")) > 0) {
      p=l; st=(p in OF) ? "apagada" : "activa"
      if (FL[p] ~ /PERSISTENT/) v="nunca"
      else if (p in NV) v="nunca"
      else if (p in KP) v="conservar"
      else if (p in SF) v="seguro"
      else v="revisar"
      name=(p in NM) ? NM[p] : ""
      if (FL[p] ~ /PERSISTENT/) name=(name=="" ? "" : name " ") "(Android la mantiene corriendo)"
      printf "%d\t%s\t%s\t%s\t%s\n", ORD[v], v, st, p, name
      C[v]++
    }
    printf "SUMMARY\t%s\t%s\t%s\n", C["nunca"]+0, C["conservar"]+0, C["seguro"]+0 > (tmp "/summary")
    printf "%d\n", C["revisar"]+0 >> (tmp "/summary")
    close(tmp "/summary")
    exit
  }
' | sort -k1,1n -k4,4 | cut -f2-

[ -s "$tmp/summary" ] || { echo "No se pudo ordenar la lista de apps. No se cambió nada." >&2; exit 1; }
n() { awk -v k="$1" 'NR==1{print $k}' "$tmp/summary" 2>/dev/null; }
echo
echo "nunca $(n 2) | conservar $(n 3) | seguro $(n 4) | revisar $(awk 'NR==2{print $1}' "$tmp/summary" 2>/dev/null)"
echo
echo "seguro = relleno preinstalado común. revisar = desconocida, déjala encendida salvo que sepas qué es."
echo "Antes de apagar algo, lee docs/debloat.md y confirma cada cambio antes de hacerlo."
