#!/bin/sh
# Compila out/tvhome.apk. Necesita Java 17 y el Android SDK (plataforma 34, build-tools 34).
#   macOS:  brew install openjdk@17 && brew install --cask android-commandlinetools
#           sdkmanager "platforms;android-34" "build-tools;34.0.0"
# Para usar otra lista de apps: APPS=mis-apps.txt sh build.sh
set -e
cd "$(dirname "$0")"

[ -n "$JAVA_HOME" ] || for j in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17 /usr/lib/jvm/java-17-openjdk-amd64; do [ -d "$j" ] && JAVA_HOME=$j && break; done
[ -n "$JAVA_HOME" ] && export PATH="$JAVA_HOME/bin:$PATH"
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$SDK" ] || for d in /opt/homebrew/share/android-commandlinetools "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do [ -d "$d" ] && SDK=$d && break; done
BT=$SDK/build-tools/34.0.0; JAR=$SDK/platforms/android-34/android.jar
[ -f "$JAR" ] && [ -d "$BT" ] || { echo "No se encontró el Android SDK. Define ANDROID_HOME e instala platforms;android-34 y build-tools;34.0.0." >&2; exit 1; }

rm -rf out; mkdir -p out/classes out/dex out/gen/com/ansub/tvhome
"$BT/aapt2" compile --dir res -o out/res.zip

# Convierte la lista de apps en Apps.java.
{
  echo "package com.ansub.tvhome;"
  echo "final class Apps { static final String[] LIST = {"
  grep -v '^[[:space:]]*#' "${APPS:-apps.txt}" | tr -d ' \t\r' | grep -v '^$' | sed 's/.*/    "&",/'
  echo "}; }"
} > out/gen/com/ansub/tvhome/Apps.java

"$BT/aapt2" link -o out/base.apk -I "$JAR" --manifest AndroidManifest.xml out/res.zip --min-sdk-version 21 --target-sdk-version 34
# shellcheck disable=SC2046 # javac y d8 quieren un argumento por archivo, así que la lista se separa a propósito
javac -nowarn -Xlint:-options -encoding UTF-8 -source 1.8 -target 1.8 -bootclasspath "$JAR:$BT/core-lambda-stubs.jar" \
  -d out/classes $(find src out/gen -name "*.java")
# shellcheck disable=SC2046 # igual aquí
"$BT/d8" --min-api 21 --release --lib "$JAR" --output out/dex $(find out/classes -name '*.class')
cp out/base.apk out/unsigned.apk; (cd out/dex && zip -q ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 out/unsigned.apk out/aligned.apk

# La llave de firma se crea en la primera compilación, con una contraseña al azar guardada en key.pass.
# Conserva key.jks y key.pass: las actualizaciones deben firmarse con la misma llave.
# (Para otra llave: define KEYSTORE y KEYSTORE_PASS.)
KS=${KEYSTORE:-key.jks}; PASS_FILE=key.pass
if [ -n "$KEYSTORE_PASS" ]; then PASS=$KEYSTORE_PASS
elif [ -f "$PASS_FILE" ]; then PASS=$(cat "$PASS_FILE")
elif [ ! -f "$KS" ]; then
  PASS=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  (umask 077; printf '%s\n' "$PASS" > "$PASS_FILE")
else
  echo "Existe $KS pero no su contraseña. Define KEYSTORE_PASS o crea $PASS_FILE con ella." >&2; exit 1
fi
# La contraseña viaja por una variable de entorno, no en la línea de comandos (ahí la ve cualquier proceso).
export TVHOME_KS_PASS="$PASS"
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass:env TVHOME_KS_PASS -keypass:env TVHOME_KS_PASS \
  -alias tvhome -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=tvhome" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass env:TVHOME_KS_PASS --out out/tvhome.apk out/aligned.apk
echo "Listo: out/tvhome.apk"
