# ScanOrder Logo

## File
- `scanorder_logo.svg` - Full logo with text (for branding, web, splash)
- `scanorder_icon.svg` - Icon only (for Android/iOS app icon)

## Meaning
Logo menggambarkan konsep aplikasi **ScanOrder**:
- **Kotak / Package** = Order / pesanan
- **Barcode** = Scan / pemindaian
- **Laser merah** = Scanner aktif sedang membaca
- **Sudut scanner** = Frame kamera barcode scanner
- **Warna biru** = Profesional, teknologi, trust

## Cara pakai di Android

### 1. Convert SVG ke PNG (per density)
Gunakan tool online seperti:
- https://convertio.co/svg-png/
- https://cloudconvert.com/svg-to-png
- Atau Inkscape / Figma

Ukuran yang dibutuhkan:
| Density | Size (px) |
|---------|-----------|
| mdpi    | 48 x 48   |
| hdpi    | 72 x 72   |
| xhdpi   | 96 x 96   |
| xxhdpi  | 144 x 144 |
| xxxhdpi | 192 x 192 |

Simpan ke:
```
android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
...
```

### 2. Adaptive Icon (Android 8+)
Buat 2 layer dari SVG:
- **Foreground**: Icon utama (tanpa background)
- **Background**: Warna gradasi biru `#2563EB` ke `#1E40AF`

Simpan sebagai:
```
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
android/app/src/main/res/drawable/ic_launcher_foreground.xml
android/app/src/main/res/drawable/ic_launcher_background.xml
```

### 3. Flutter Launcher Icons (paling mudah)
Tambah di `pubspec.yaml`:
```yaml
flutter_icons:
  android: true
  ios: true
  image_path: "assets/logo/scanorder_icon.png"
  adaptive_icon_background: "#2563EB"
  adaptive_icon_foreground: "assets/logo/scanorder_icon.png"
```

Jalankan:
```bash
flutter pub add flutter_launcher_icons
flutter pub run flutter_launcher_icons
```
