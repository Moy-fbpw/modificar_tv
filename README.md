# modificar_tv

Herramientas para limpiar una Android TV y hacerla más rápida: apagar apps de relleno y anuncios,
quitar animaciones y, como opción, cambiar la pantalla de inicio por una más ligera.

Uso personal. Basado en el proyecto tv-detox (commit `2ac1ee6`, versión 1.5.3), traducido y adaptado.

## Qué hay aquí

| Archivo | Qué hace |
| --- | --- |
| `candidates.sh` | Lista todas las apps de la TV con un veredicto (`nunca`, `conservar`, `seguro`, `revisar`). Solo lee. |
| `docs/debloat.md` | Las reglas para decidir qué apagar sin riesgo. |
| `build.sh` | Compila la pantalla de inicio (`out/tvhome.apk`). |
| `install.sh` | Instala la pantalla de inicio y la deja como predeterminada. |
| `undo.sh` | Quita la pantalla de inicio y regresa la original. |
| `check.sh` | Revisa que una actualización de la TV no haya deshecho la limpieza. |
| `apps.txt` | Apps de la fila principal de la pantalla de inicio. |
| `src/`, `AndroidManifest.xml` | Código de la pantalla de inicio. No pide permiso de internet. |

## Lo que necesitas

- `adb` en la computadora: `brew install android-platform-tools`.
- La computadora y la TV en la misma red.
- Para compilar la pantalla de inicio: Java 17 y el Android SDK (ver el encabezado de `build.sh`).

## Pasos

### 1. Activa la depuración en la TV

Configuración → Preferencias del dispositivo → Información → presiona **Compilación** 7 veces.
Luego, en **Opciones para desarrolladores**, activa **Depuración por USB** (y **Depuración por red**
si tu TV la tiene).

### 2. Conéctate

```
adb connect <IP_TV>
```

La TV pregunta «¿Permitir depuración?». Elige **Permitir** y marca **Permitir siempre**.

### 3. Revisa qué tiene la TV

```
sh candidates.sh <IP_TV>
```

No cambia nada. Guarda la salida: es la base para decidir.

### 4. Limpia por tandas

Sigue [docs/debloat.md](docs/debloat.md): apaga de 5 a 10 apps, reinicia y prueba la TV. Anota cada
cambio en una lista (por ejemplo `mi-tv.txt`) con el formato de `check.sh`:

```
apagar com.ejemplo.app
global window_animation_scale 0
```

O pídeselo a Claude Code con este prompt:

```text
Ayúdame a limpiar mi Android TV y hacerla más rápida.
Mi TV es una <marca y modelo>. Usa los scripts de este repo.

1. Antes de cambiar nada, dime en palabras simples que esto apaga
   apps del sistema y que tiene riesgo. Pídeme confirmar.
2. Conéctate a la TV por la red. Guíame en lo que tenga que hacer en la TV.
3. Ejecuta candidates.sh y, antes de cambiar nada, lista cada app en
   lenguaje normal: segura de apagar, necesaria para la TV y apps que uso.
   Revisa la memoria libre.
4. Pregúntame antes de cada cambio. Apaga en vez de desinstalar.
   Anota cada cambio en mi-tv.txt con el formato de check.sh.
5. Nunca apagues: servicios de Google Play (com.google.android.gms),
   Google Play, Configuración, la interfaz del sistema, apps de
   configuración inicial, el teclado, Bluetooth, mis entradas HDMI,
   el framework de entradas y sintonizador, ni nada que la TV necesite
   para arrancar. Si tienes duda, déjala encendida.
6. Quita las animaciones y haz que la TV se suspenda tras 5 minutos.
   Revisa el modelo y pregúntame si es OLED; si lo es, deja el
   protector de pantalla encendido.
7. Espera 30 segundos después del último cambio, reinicia la TV una
   vez y revisa que arranque normal antes de decir que terminaste.
   Muéstrame la memoria libre antes y después.
8. Al final, recuérdame apagar la depuración en la TV.
```

### 5. (Opcional) Instala la pantalla de inicio

```
sh build.sh
sh install.sh <IP_TV>                                   # elige tus apps
sh install.sh <IP_TV> "com.netflix.ninja,com.google.android.youtube.tv"
sh install.sh <IP_TV> "" "bluetooth,sound,picture"      # accesos junto al reloj
```

En Android TV, `install.sh` te pregunta antes de apagar la pantalla de inicio original.

### 6. Apaga la depuración

En **Opciones para desarrolladores**, apaga la depuración por USB y por red. Si se queda encendida,
otros dispositivos de tu red pueden pedir controlar la TV. Solo vuelve a encenderla para `undo.sh`,
`check.sh` o cambios nuevos.

## Revisar después de una actualización

```
sh check.sh <IP_TV>                    # revisa la pantalla de inicio
sh check.sh <IP_TV> --fix              # y la corrige
sh check.sh <IP_TV> --fix mi-tv.txt    # también revisa tu lista de cambios
```

## Deshacer

```
sh undo.sh <IP_TV>
```

Regresa la pantalla de inicio original y quita la nueva. Las apps que apagaste a mano se regresan
con `adb shell pm enable <paquete>`, o todas de una vez:

```
for p in $(adb shell pm list packages -d | tr -d '\r' | sed 's/package://'); do adb shell pm enable "$p"; done
```
