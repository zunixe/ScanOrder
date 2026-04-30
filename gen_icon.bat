@echo off
echo === Step 1: flutter pub get === > gen_icon_log.txt 2>&1
flutter pub get >> gen_icon_log.txt 2>&1
echo === Step 2: flutter_launcher_icons === >> gen_icon_log.txt 2>&1
flutter pub run flutter_launcher_icons >> gen_icon_log.txt 2>&1
echo === Step 3: verify mipmap === >> gen_icon_log.txt 2>&1
dir "android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png" >> gen_icon_log.txt 2>&1
echo === Done === >> gen_icon_log.txt 2>&1
