#!/usr/bin/env bash
# ============================================================
# Build USER APK untuk testing/sideload (flavor play)
#
# SELALU pakai script ini. Membersihkan cache inkremental dulu
# supaya tidak pernah dapat APK berisi kode lama (CONFIG.md §8).
#
# Pemakaian:
#   ./scripts/build_play_apk.sh
#
# Output:
#   build/app/outputs/flutter-apk/app-play-release.apk
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/3] Bersihkan cache build inkremental…"
rm -rf build .dart_tool/flutter_build

echo "[2/3] Build play APK (release)…"
flutter build apk --release --flavor play --dart-define-from-file=.env

APK="build/app/outputs/flutter-apk/app-play-release.apk"
echo "[3/3] Selesai."
echo "Artifact : $APK"
echo "MD5      : $(md5 -q "$APK")"
echo "Waktu    : $(date)"
