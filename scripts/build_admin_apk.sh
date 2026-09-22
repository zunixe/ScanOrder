#!/usr/bin/env bash
# ============================================================
# Build ADMIN APK (ScanOrder Admin — internal, JANGAN upload store)
#
# SELALU pakai script ini untuk build rilis. Script membersihkan
# cache inkremental Flutter dulu (terbukti pernah korup sehingga
# APK berisi kode lama padahal build sukses — lihat CONFIG.md §8).
#
# Pemakaian:
#   ./scripts/build_admin_apk.sh
#
# Output:
#   build/app/outputs/flutter-apk/app-admin-release.apk
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/3] Bersihkan cache build inkremental…"
rm -rf build .dart_tool/flutter_build

echo "[2/3] Build admin APK (release)…"
flutter build apk --release --flavor admin -t lib/main_admin.dart --dart-define-from-file=.env

APK="build/app/outputs/flutter-apk/app-admin-release.apk"
echo "[3/3] Selesai."
echo "Artifact : $APK"
echo "MD5      : $(md5 -q "$APK")"
echo "Waktu    : $(date)"
