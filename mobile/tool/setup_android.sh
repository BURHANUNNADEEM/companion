#!/usr/bin/env bash
# Generates the standard Flutter Android scaffolding that is not checked in (Gradle wrapper, launcher icons,
# styles, local.properties) WITHOUT overwriting Companion's own files, then fetches packages.
# Requires Flutter >= 3.29 (Kotlin-DSL Gradle templates).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter --version
flutter create --platforms=android --org com.companion --project-name companion . >/dev/null

# flutter create adds a template MainActivity under com/companion/companion - ours lives in com/companion/app.
rm -rf android/app/src/main/kotlin/com/companion/companion
# Older Flutter versions generate Groovy files next to our .kts files; remove them to avoid conflicts.
rm -f android/build.gradle android/settings.gradle android/app/build.gradle
# Template widget test refers to a counter app that does not exist here.
grep -q "Counter increments" test/widget_test.dart 2>/dev/null && git checkout -- test/widget_test.dart 2>/dev/null || true

flutter pub get
echo "Android scaffolding ready. Next: flutter test && flutter run --flavor demo --dart-define=AUTH_MODE=dev"
