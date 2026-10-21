#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
tools_path="$sdk_path/build-tools/35.0.0"
platform_path="$sdk_path/platforms/android-35/android.jar"
mkdir -p build/classes build/dex build/package
"$tools_path/aapt2" compile --dir res -o build/resources.zip
"$tools_path/aapt2" link -o build/package/unsigned.apk -I "$platform_path" --manifest AndroidManifest.xml -A assets build/resources.zip
javac -source 8 -target 8 -classpath "$platform_path" -d build/classes $(find src -name '*.java')
jar cf build/classes.jar -C build/classes .
"$tools_path/d8" --min-api 26 --lib "$platform_path" --output build/dex build/classes.jar
cp build/package/unsigned.apk build/package/with-dex.apk
(cd build/dex && zip -q ../package/with-dex.apk classes.dex)
"$tools_path/zipalign" -p -f 4 build/package/with-dex.apk build/package/aligned.apk
key_path="$HOME/.android/frs-technician-demo.keystore"
mkdir -p "$(dirname "$key_path")"
if [ ! -f "$key_path" ]; then
    keytool -genkeypair -keystore "$key_path" -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=FRS Technician Demo,O=Android Demo,C=ZA'
fi
"$tools_path/apksigner" sign --ks "$key_path" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out ../Fire_Risk_Systems_Technician_Demo.apk build/package/aligned.apk
"$tools_path/apksigner" verify --verbose --print-certs ../Fire_Risk_Systems_Technician_Demo.apk
"$tools_path/aapt2" dump badging ../Fire_Risk_Systems_Technician_Demo.apk
sha256sum ../Fire_Risk_Systems_Technician_Demo.apk > ../Fire_Risk_Systems_Technician_Demo.apk.sha256
