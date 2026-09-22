#!/usr/bin/env bash
# ============================================================
# Build USER AAB untuk Google Play (flavor play)
#
# SELALU pakai script ini untuk build rilis Play. Script
# membersihkan cache inkremental Flutter dulu (terbukti pernah
# korup sehingga AAB berisi kode lama — lihat CONFIG.md §8).
#
# Pemakaian:
#   ./scripts/build_play_aab.sh
#
# Output (upload ini ke Play Console / fastlane):
#   build/app/outputs/bundle/playRelease/app-play-release.aab
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/3] Bersihkan cache build inkremental…"
rm -rf build .dart_tool/flutter_build

echo "[2/3] Build play AAB (release)…"
flutter build appbundle --release --flavor play --dart-define-from-file=.env

AAB="build/app/outputs/bundle/playRelease/app-play-release.aab"
echo "[3/3] Selesai."
echo "Artifact : $AAB"
echo "MD5      : $(md5 -q "$AAB")"
echo "Waktu    : $(date)"
