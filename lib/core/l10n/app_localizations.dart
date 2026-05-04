import 'package:flutter/material.dart';

/// Abstract base class for localization strings
abstract class AppStrings {
  String get appName;
  String get scanHistory;
  String get searchResi;
  String get scanResi;
  String get allDates;
  String get scans;
  String get noDataToExport;
  String get exportCsv;
  String get exportXlsx;
  String get exportCsvSubtitle;
  String get exportXlsxSubtitle;
  String get upgradeForExcel;
  String get dataSavedLocally;
  String get loginForBackup;
  String get login;
  String get category;
  String get marketplace;
  String get date;
  String get time;
  String get delete;
  String get editPhoto;
  String get takePhoto;
  String get chooseFromGallery;
  String get removePhoto;
  String get cancel;
  String get confirm;
  String get deleteConfirm;
  String get stats;
  String get totalScans;
  String get todayScans;
  String get thisWeekScans;
  String get settings;
  String get subscription;
  String get contactSupport;
  String get about;
  String get version;
  String get logout;
  String get deleteAccount;
  String get deleteAccountConfirm;
  String get freeTier;
  String get proTier;
  String get teamTier;
  String get unlimitedTier;
  String get loading;
  String get error;
  String get retry;
  String get noScansFound;
  String get startScanning;
}

/// App localization strings for Indonesian (default)
class AppStringsId extends AppStrings {
  @override String get appName => 'ScanOrder';
  @override String get scanHistory => 'Riwayat Scan';
  @override String get searchResi => 'Cari nomor resi...';
  @override String get scanResi => 'Scan resi';
  @override String get allDates => 'Semua';
  @override String get scans => 'scan';
  @override String get noDataToExport => 'Tidak ada data untuk di-export';
  @override String get exportCsv => 'Export CSV';
  @override String get exportXlsx => 'Export XLSX (Excel)';
  @override String get exportCsvSubtitle => 'Format tabel, bisa dibuka di semua app';
  @override String get exportXlsxSubtitle => 'Format Excel';
  @override String get upgradeForExcel => 'Upgrade ke paket berbayar untuk export Excel';
  @override String get dataSavedLocally => 'Data tersimpan lokal';
  @override String get loginForBackup => 'Login untuk backup & sync ke cloud';
  @override String get login => 'Login';
  @override String get category => 'Kategori';
  @override String get marketplace => 'Marketplace';
  @override String get date => 'Tanggal';
  @override String get time => 'Waktu';
  @override String get delete => 'Hapus';
  @override String get editPhoto => 'Edit Foto';
  @override String get takePhoto => 'Ambil Foto';
  @override String get chooseFromGallery => 'Pilih dari Galeri';
  @override String get removePhoto => 'Hapus Foto';
  @override String get cancel => 'Batal';
  @override String get confirm => 'Konfirmasi';
  @override String get deleteConfirm => 'Yakin ingin menghapus scan ini?';
  @override String get stats => 'Statistik';
  @override String get totalScans => 'Total Scan';
  @override String get todayScans => 'Scan Hari Ini';
  @override String get thisWeekScans => 'Scan Minggu Ini';
  @override String get settings => 'Pengaturan';
  @override String get subscription => 'Langganan';
  @override String get contactSupport => 'Hubungi Support';
  @override String get about => 'Tentang';
  @override String get version => 'Versi';
  @override String get logout => 'Logout';
  @override String get deleteAccount => 'Hapus Akun';
  @override String get deleteAccountConfirm => 'Yakin ingin menghapus akun? Semua data akan hilang permanen.';
  @override String get freeTier => 'Gratis';
  @override String get proTier => 'Pro';
  @override String get teamTier => 'Tim';
  @override String get unlimitedTier => 'Unlimited';
  @override String get loading => 'Memuat...';
  @override String get error => 'Terjadi kesalahan';
  @override String get retry => 'Coba Lagi';
  @override String get noScansFound => 'Tidak ada scan ditemukan';
  @override String get startScanning => 'Mulai Scan';
}

/// App localization strings for English
class AppStringsEn extends AppStrings {
  @override String get appName => 'ScanOrder';
  @override String get scanHistory => 'Scan History';
  @override String get searchResi => 'Search tracking number...';
  @override String get scanResi => 'Scan tracking';
  @override String get allDates => 'All';
  @override String get scans => 'scans';
  @override String get noDataToExport => 'No data to export';
  @override String get exportCsv => 'Export CSV';
  @override String get exportXlsx => 'Export XLSX (Excel)';
  @override String get exportCsvSubtitle => 'Table format, opens in all apps';
  @override String get exportXlsxSubtitle => 'Excel format';
  @override String get upgradeForExcel => 'Upgrade to paid plan for Excel export';
  @override String get dataSavedLocally => 'Data saved locally';
  @override String get loginForBackup => 'Login to backup & sync to cloud';
  @override String get login => 'Login';
  @override String get category => 'Category';
  @override String get marketplace => 'Marketplace';
  @override String get date => 'Date';
  @override String get time => 'Time';
  @override String get delete => 'Delete';
  @override String get editPhoto => 'Edit Photo';
  @override String get takePhoto => 'Take Photo';
  @override String get chooseFromGallery => 'Choose from Gallery';
  @override String get removePhoto => 'Remove Photo';
  @override String get cancel => 'Cancel';
  @override String get confirm => 'Confirm';
  @override String get deleteConfirm => 'Are you sure you want to delete this scan?';
  @override String get stats => 'Statistics';
  @override String get totalScans => 'Total Scans';
  @override String get todayScans => "Today's Scans";
  @override String get thisWeekScans => "This Week's Scans";
  @override String get settings => 'Settings';
  @override String get subscription => 'Subscription';
  @override String get contactSupport => 'Contact Support';
  @override String get about => 'About';
  @override String get version => 'Version';
  @override String get logout => 'Logout';
  @override String get deleteAccount => 'Delete Account';
  @override String get deleteAccountConfirm => 'Are you sure you want to delete your account? All data will be permanently lost.';
  @override String get freeTier => 'Free';
  @override String get proTier => 'Pro';
  @override String get teamTier => 'Team';
  @override String get unlimitedTier => 'Unlimited';
  @override String get loading => 'Loading...';
  @override String get error => 'An error occurred';
  @override String get retry => 'Retry';
  @override String get noScansFound => 'No scans found';
  @override String get startScanning => 'Start Scanning';
}

/// Localization provider for internationalization
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  late final AppStrings _strings = locale.languageCode == 'en' 
      ? AppStringsEn() 
      : AppStringsId();

  String get appName => _strings.appName;
  String get scanHistory => _strings.scanHistory;
  String get searchResi => _strings.searchResi;
  String get scanResi => _strings.scanResi;
  String get allDates => _strings.allDates;
  String get scans => _strings.scans;
  String get noDataToExport => _strings.noDataToExport;
  String get exportCsv => _strings.exportCsv;
  String get exportXlsx => _strings.exportXlsx;
  String get exportCsvSubtitle => _strings.exportCsvSubtitle;
  String get exportXlsxSubtitle => _strings.exportXlsxSubtitle;
  String get upgradeForExcel => _strings.upgradeForExcel;
  String get dataSavedLocally => _strings.dataSavedLocally;
  String get loginForBackup => _strings.loginForBackup;
  String get login => _strings.login;
  String get category => _strings.category;
  String get marketplace => _strings.marketplace;
  String get date => _strings.date;
  String get time => _strings.time;
  String get delete => _strings.delete;
  String get editPhoto => _strings.editPhoto;
  String get takePhoto => _strings.takePhoto;
  String get chooseFromGallery => _strings.chooseFromGallery;
  String get removePhoto => _strings.removePhoto;
  String get cancel => _strings.cancel;
  String get confirm => _strings.confirm;
  String get deleteConfirm => _strings.deleteConfirm;
  String get stats => _strings.stats;
  String get totalScans => _strings.totalScans;
  String get todayScans => _strings.todayScans;
  String get thisWeekScans => _strings.thisWeekScans;
  String get settings => _strings.settings;
  String get subscription => _strings.subscription;
  String get contactSupport => _strings.contactSupport;
  String get about => _strings.about;
  String get version => _strings.version;
  String get logout => _strings.logout;
  String get deleteAccount => _strings.deleteAccount;
  String get deleteAccountConfirm => _strings.deleteAccountConfirm;
  String get freeTier => _strings.freeTier;
  String get proTier => _strings.proTier;
  String get teamTier => _strings.teamTier;
  String get unlimitedTier => _strings.unlimitedTier;
  String get loading => _strings.loading;
  String get error => _strings.error;
  String get retry => _strings.retry;
  String get noScansFound => _strings.noScansFound;
  String get startScanning => _strings.startScanning;
}

/// Localizations delegate for AppLocalizations
class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  final Locale locale;

  AppLocalizationsDelegate(this.locale);

  @override
  bool isSupported(Locale locale) => ['id', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

/// Supported locales
const List<Locale> kSupportedLocales = [
  Locale('id'),
  Locale('en'),
];
