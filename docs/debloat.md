# Limpiar la TV sin riesgo

Este repo hace dos trabajos. La pantalla de inicio es automática. Apagar el relleno es una
decisión app por app, así que la toma quien conduce la limpieza. Esta página es ese criterio,
más las reglas que la mantienen reversible.

Empieza con `sh candidates.sh <IP_TV>`. Lista todas las apps de la TV con un veredicto y no
cambia nada:

| veredicto | significado |
| --- | --- |
| `nunca` | la TV la necesita, o Android la mantiene corriendo hagas lo que hagas. Déjala encendida. |
| `conservar` | trae una función que podrías usar: transmitir, buscar o TV en vivo. Apágala solo si no la usas. |
| `seguro` | relleno preinstalado común: anuncios, filas patrocinadas, apps de fábrica y de Google sin uso. |
| `revisar` | no se sabe nada de ella. Déjala encendida salvo que sepas qué es. |

Avanza en la lista de arriba hacia abajo. Apaga, espera y revisa que la TV siga funcionando.

## Las cuatro reglas

### 1. Apaga las apps, nunca las desinstales

`pm disable-user --user 0 <paquete>` oculta una app y `pm enable <paquete>` la regresa.
`pm uninstall` sobre una app del sistema no se puede deshacer desde la TV. Todo lo que se haga en
la TV debe poder revertirse desde la TV, así que apaga, y anota cada paquete que toques en la
lista para deshacer.

### 2. Nunca apagues lo que arranca la TV

La pantalla, el control remoto, el teclado, la app de configuración y el instalador de paquetes
son piezas de carga. Si apagas una, puedes terminar con una TV que arranca en pantalla negra, y
ADB es tu único camino de regreso. `candidates.sh` las marca como `nunca`.

### 3. Las apps que Android marca como PERSISTENT no se pueden apagar

Algunas apps se reinician solas en cuanto arranca el sistema. `pm disable-user` dirá que
funcionó y la app regresa después de reiniciar:

```
adb shell dumpsys package com.tcl.guard | grep -m1 pkgFlags
# pkgFlags=[ SYSTEM HAS_CODE PERSISTENT ALLOW_CLEAR_USER_DATA ... ]
```

Si ves `PERSISTENT`, no la toques. Apagarla no se queda y, en algunas TVs, altera el sistema.
`candidates.sh` también las marca como `nunca`.

### 4. Si transmites desde el celular, pruébalo

Transmitir no es una sola app que se reconozca por el nombre. En Google TV el receptor es
`com.google.android.apps.mediashell`, y es fácil apagarlo al barrer nombres que suenan a
«media». Déjalo encendido y, después de una tanda que haya tocado algo de Google, transmite un
video desde tu celular y confirma que la TV sigue apareciendo. Si no aparece,
`pm enable com.google.android.apps.mediashell` y reinicia. En una TV a la que nunca le
transmites, se puede apagar sin problema.

## El nombre del paquete no siempre es la app

Un nombre de paquete no siempre dice qué app es. Prime Video, por ejemplo, se instala como
`com.amazon.amazonvideo.livingroom`, y Netflix como `com.netflix.ninja`. Antes de apagar algo,
revisa qué tiene adentro:

```
adb shell cmd package resolve-activity --brief <paquete>
```

Si es una app que instalaste y usas, va con tus apps, se llame como se llame.

## Hazlo por tandas

Apaga de cinco a diez apps y revisa la TV: cambia de entrada, abre la configuración, reproduce
algo, transmite algo. Cuando una tanda salga limpia, sigue con la próxima. Si la TV falla, sabes
qué tanda deshacer, en vez de adivinar entre cuarenta cambios.

Vale la pena reiniciar después de cada tanda. Apagar una app parece instantáneo, pero sus
procesos y servicios pueden seguir vivos hasta que el sistema reinicia, así que la TV solo
queda probada de verdad tras un arranque limpio.

## Si algo sale mal

- Regresar una app: `adb shell pm enable <paquete>`
- Regresar los launchers que apagó `install.sh`: `sh undo.sh <IP_TV>`. Solo conoce lo que apagó
  `install.sh`. Las apps que apagues a mano siguiendo esta guía no están en su lista, así que
  anota cada una conforme avances y vuelve a encenderlas con `pm enable`.
- Pantalla negra pero la TV responde a ADB: vuelve a encender `com.google.android.tvlauncher`,
  arranca con ella y ejecuta `undo.sh`.

## Lo que no es un paquete

Algunas molestias son comportamiento de la TV, no una app. Una TV que abre TV en vivo o una
entrada al arrancar está configurada así en sus propios ajustes, casi siempre en el menú de
sistema o de energía. No hay paquete que apagar: cámbialo con el control remoto.

## Referencia

> Las listas vienen de TVs TCL y Google TV. Para Hisense hay pistas al final de esta página, todavía
> sin confirmar en tu TV.

### Nunca apagar

| paquete | qué es |
| --- | --- |
| `com.google.android.gms`, `com.google.android.gsf` | Servicios y framework de Google Play |
| `com.android.vending` | Google Play Store |
| `com.android.tv.settings`, `com.android.settings` | Configuración |
| `com.android.systemui` | Interfaz del sistema |
| `com.android.providers.*` | almacenamiento de ajustes, medios, contactos y descargas |
| `com.android.bluetooth` | Bluetooth y el control remoto |
| `com.android.packageinstaller`, `com.google.android.packageinstaller` | instalar apps |
| `com.dolby.android.audio.service` | procesamiento de audio; en algunas TVs sin él no hay sonido |
| teclados | `com.google.android.inputmethod.latin` (Gboard), `com.android.inputmethod.latin`, `com.tcl.inputmethod.international` |
| apps de configuración | `com.google.android.tungsten.setupwraith`, `com.google.android.partnersetup`, `com.google.android.onetimeinitializer` |
| básicos de TCL | `com.tcl.tvinput` (HDMI y sintonizador), `com.tcl.suspension` (selector de entradas), `com.tcl.providers.config`, `com.tcl.useragreement` |
| `com.google.android.apps.mediashell` | transmitir, si transmites |
| cualquier app marcada `PERSISTENT` | no se va a quedar apagada |

### Comúnmente seguro apagar

Anuncios y filas patrocinadas, apps de Google sin uso, relleno del fabricante y restos de puerto serie:

| paquete | qué es |
| --- | --- |
| `com.google.android.tvrecommendations` | fila patrocinada de Google TV |
| `com.google.android.backdrop` | anuncios de fondo de Google TV |
| `com.google.android.videos`, `com.google.android.youtube.tvmusic`, `com.google.android.play.games` | apps de Google que pocas TVs usan |
| `com.google.android.feedback` | comentarios a Google |
| `com.tcl.waterfall.overseas`, `com.tcl.esticker` | contenido y etiquetas de TCL |
| `com.tcl.dashboard`, `com.tcl.messagebox` | paneles y avisos emergentes de TCL |
| `com.tcl.copydatatotv`, `com.tcl.audioplayer`, `com.tcl.imageplayer`, `com.tcl.videoplayer` | ayudantes multimedia de TCL |
| `com.tcl.usercenter`, `com.tcl.keyhelp` | cuenta y ayuda de TCL |
| `com.android.printspooler`, `com.android.htmlviewer` | piezas sobrantes de Android |

### Depende de ti

Apágalas solo si no usas la función:

| paquete | función |
| --- | --- |
| `com.google.android.apps.mediashell` | transmitir desde el celular |
| `com.google.android.katniss` | búsqueda y voz de Google TV |
| `com.google.android.tv.assistant` | Asistente de Google |
| `com.google.android.marvin.talkback` | lector de pantalla TalkBack |
| `com.google.android.tv.remote.service` | control remoto desde el celular |
| `com.google.android.tts` | texto a voz |
| `com.tcl.tv` | TV en vivo, canales de antena y cable |
| `com.android.dreams.basic`, `com.google.android.apps.tv.dreamx` | el protector de pantalla. Déjalo en una TV OLED: evita que la imagen se queme |

Los fabricantes cambian y agregan nombres a estas listas, así que tómalas como pistas fuertes,
no como verdad absoluta. Si tienes duda, déjala encendida: una TV lenta es mejor que una TV que
no puedes usar.

## Hisense (pistas por confirmar)

Recopilado en octubre de 2026 de listas comunitarias para Hisense con Android TV 9 (HiSmartTV A4),
Android 11 con Google TV (`songshan`) y Google TV 12 (FFM). Los nombres cambian entre modelos y
firmware: `candidates.sh` todavía no las conoce por nombre, y solo pasan a las listas de arriba
cuando se prueben en tu TV. Si tu Hisense dice VIDAA, no es Android y nada de esto aplica.

### Nunca apagar (Hisense)

| paquete | qué es |
| --- | --- |
| `com.hisense.tv.smartsense`, `com.vt.tv.smartsense.ui`, `com.vt.tv.aiot` | familia smartsense / AIoT. En varios modelos, apagarla mandó la TV a Android Recovery al reiniciar |
| `com.hisense.tv.hitvinput`, `com.vt.tv.input` | entradas de TV (HDMI y sintonizador) |
| `com.mediatek.*` | piezas del chip MediaTek. Ninguna lista las toca |
| `com.jamdeo.tv.livetv`, `com.jamdeo.tv.vod` | TV en vivo y launcher de fábrica en algunos modelos |
| `com.google.android.tvlauncher` | launcher original: es el respaldo de `undo.sh` |

Confirmado en una 40A45H (Android TV 14, firmware `huashan`, MT5867): no trae smartsense/AIoT, y
`com.netflix.ninja` y `com.google.android.tvrecommendations` se vuelven a encender solas en cada arranque
(a Netflix la reactiva `NetflixObserver`, dentro de `com.mediatek.tv.service`). No vale la pena apagarlas.

### Comúnmente apagadas en Hisense

| paquete | qué es |
| --- | --- |
| `com.hisense.app.logreport` | envía registros del sistema a Hisense |
| `com.hisense.service.message` | avisos y mensajes promocionales de Hisense |
| `com.hisense.storemode`, `fusion.android.tv.demo` | modo tienda y video de demostración |
| `com.mstar.android.tv.disclaimercustomization` | pantalla de aviso del modo tienda |
| `com.hisense.tv.b2b` | modo hotel o negocio |
| `android.autoinstalls.config.hisense.xiaoyushan` | instala apps de socios sin preguntar |
| `net.vidaatv.hisense.android.tv` | canales gratis con anuncios de VIDAA |
| `com.google.android.leanbacklauncher.recommendations` | recomendaciones del launcher |
| `com.google.android.tv.bugreportsender` | envía reportes de fallas a Google |
| `com.hisense.hibrowser` | navegador de Hisense |

### Depende de ti (Hisense)

| paquete | función |
| --- | --- |
| `com.hisense.evservice` | reconoce lo que ves para anuncios (ACR). También vigila las entradas HDMI: después de apagarlo, prueba cada HDMI |
| `com.hisense.tv.ota`, `com.hisense.remoteupgrade` | actualizaciones del sistema. Apagarlas evita que una actualización deshaga la limpieza, pero también corta los parches |
| `com.jamdeo.tv.mediacenter` | reproductor de USB y DLNA |
| `com.vt.miracast` | duplicar la pantalla del celular (Miracast) |
