#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ ОШИБКА в post-create.sh: строка $LINENO" >&2; exit 1' ERR

ANDROID_SDK="/workspaces/android-sdk"
FLUTTER_ROOT="/workspaces/flutter"
FLUTTER_VERSION="3.44.3"   # = CI (subosito/flutter-action) и старый ПК

step() { echo; echo "===== $1 ====="; }

step "Android SDK"
if [ ! -x "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "скачиваю cmdline-tools..."
  mkdir -p "$ANDROID_SDK/cmdline-tools"
  ( cd "$ANDROID_SDK/cmdline-tools" &&
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O tools.zip &&
    unzip -q tools.zip && mv cmdline-tools latest && rm tools.zip )
else
  echo "уже установлен, пропускаю"
fi

step "Android: лицензии + пакеты"
printf 'y\n%.0s' {1..20} | "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null
"$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-35" "build-tools;35.0.0"
echo "ok"

step "Flutter SDK $FLUTTER_VERSION"
if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  echo "скачиваю ~1 GB..."
  wget -q --show-progress "$URL" -O /tmp/flutter.tar.xz
  rm -rf "$FLUTTER_ROOT"
  tar -xJf /tmp/flutter.tar.xz -C /workspaces
  rm /tmp/flutter.tar.xz
else
  echo "уже установлен: $($FLUTTER_ROOT/bin/flutter --version 2>/dev/null | head -1)"
fi

step "android/local.properties"
if [ -d android ] && [ ! -f android/local.properties ]; then
  printf 'sdk.dir=%s\nflutter.sdk=%s\n' "$ANDROID_SDK" "$FLUTTER_ROOT" > android/local.properties
  echo "создан"
else
  echo "пропускаю"
fi

step "flutter pub get"
export PATH="$FLUTTER_ROOT/bin:$PATH"
flutter config --no-analytics
if [ -f pubspec.yaml ]; then flutter pub get; fi

step "flutter doctor"
flutter doctor -v
echo
echo "✅ post-create.sh завершён успешно"
