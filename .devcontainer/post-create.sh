#!/usr/bin/env bash
# .devcontainer/post-create.sh
set -euo pipefail
SDK="$HOME/android-sdk"
mkdir -p "$SDK/cmdline-tools" && cd "$SDK/cmdline-tools"

# свежую ссылку смотри на developer.android.com/studio → "Command line tools only"
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O tools.zip
unzip -q tools.zip && mv cmdline-tools latest && rm tools.zip

yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null
"$SDK/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" "platforms;android-35" "build-tools;35.0.0" >/dev/null