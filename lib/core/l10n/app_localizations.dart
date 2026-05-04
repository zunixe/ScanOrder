import 'package:flutter/material.dart';

/// App localization strings for Indonesian (default)
class AppStringsId {
  static const String appName = 'ScanOrder';
  static const String scanHistory = 'Riwayat Scan';
  static const String searchResi = 'Cari nomor resi...';
  static const String scanResi = 'Scan resi';
  static const String allDates = 'Semua';
  static const String scans = 'scan';
  static const String noDataToExport = 'Tidak ada data untuk di-export';
  static const String exportCsv = 'Export CSV';
  static const String exportXlsx = 'Export XLSX (Excel)';
  static const String exportCsvSubtitle = 'Format tabel, bisa dibuka di semua app';
  static const String exportXlsxSubtitle = 'Format Excel';
  static const String upgradeForExcel = 'Upgrade ke paket berbayar untuk export Excel';
  static const String dataSavedLocally = 'Data tersimpan lokal';
  static const String loginForBackup = 'Login untuk backup & sync ke cloud';
  static const String login = 'Login';
  static const String category = 'Kategori';
  static const String marketplace = 'Marketplace';
  static const String date = 'Tanggal';
  static const String time = 'Waktu';
  static const String delete = 'Hapus';
  static const String editPhoto = 'Edit Foto';
  static const String takePhoto = 'Ambil Foto';
  static const String chooseFromGallery = 'Pilih dari Galeri';
  static const String removePhoto = 'Hapus Foto';
  static const String cancel = 'Batal';
  static const String confirm = 'Konfirmasi';
  static const String deleteConfirm = 'Yakin ingin menghapus scan ini?';
  static const String stats = 'Statistik';
  static const String totalScans = 'Total Scan';
  static const String todayScans = 'Scan Hari Ini';
  static const String thisWeekScans = 'Scan Minggu Ini';
  static const String settings = 'Pengaturan';
  static const String subscription = 'Langganan';
  static const String contactSupport = 'Hubungi Support';
  static const String about = 'Tentang';
  static const String version = 'Versi';
  static const String logout = 'Logout';
  static const String deleteAccount = 'Hapus Akun';
  static const String deleteAccountConfirm = 'Yakin ingin menghapus akun? Semua data akan hilang permanen.';
  static const String freeTier = 'Gratis';
  static const String proTier = 'Pro';
  static const String teamTier = 'Tim';
  static const String unlimitedTier = 'Unlimited';
  static const String loading = 'Memuat...';
  static const String error = 'Terjadi kesalahan';
  static const String retry = 'Coba Lagi';
  static const String noScansFound = 'Tidak ada scan ditemukan';
  static const String startScanning = 'Mulai Scan';
}

/// App localization strings for English
class AppStringsEn {
  static const String appName = 'ScanOrder';
  static const String scanHistory = 'Scan History';
  static const String searchResi = 'Search tracking number...';
  static const String scanResi = 'Scan tracking';
  static const String allDates = 'All';
  static const String scans = 'scans';
  static const String noDataToExport = 'No data to export';
  static const String exportCsv = 'Export CSV';
  static const String exportXlsx = 'Export XLSX (Excel)';
  static const String exportCsvSubtitle = 'Table format, opens in all apps';
  static const String exportXlsxSubtitle = 'Excel format';
  static const String upgradeForExcel = 'Upgrade to paid plan for Excel export';
  static const String dataSavedLocally = 'Data saved locally';
  static const String loginForBackup = 'Login to backup & sync to cloud';
  static const String login = 'Login';
  static const String category = 'Category';
  static const String marketplace = 'Marketplace';
  static const String date = 'Date';
  static const String time = 'Time';
  static const String delete = 'Delete';
  static const String editPhoto = 'Edit Photo';
  static const String takePhoto = 'Take Photo';
  static const String chooseFromGallery = 'Choose from Gallery';
  static const String removePhoto = 'Remove Photo';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String deleteConfirm = 'Are you sure you want to delete this scan?';
  static const String stats = 'Statistics';
  static const String totalScans = 'Total Scans';
  static const String todayScans = "Today's Scans";
  static const String thisWeekScans = "This Week's Scans";
  static const String settings = 'Settings';
  static const String subscription = 'Subscription';
  static const String contactSupport = 'Contact Support';
  static const String about = 'About';
  static const String version = 'Version';
  static const String logout = 'Logout';
  static const String deleteAccount = 'Delete Account';
  static const String deleteAccountConfirm = 'Are you sure you want to delete your account? All data will be permanently lost.';
  static const String freeTier = 'Free';
  static const String proTier = 'Pro';
  static const String teamTier = 'Team';
  static const String unlimitedTier = 'Unlimited';
  static const String loading = 'Loading...';
  static const String error = 'An error occurred';
  static const String retry = 'Retry';
  static const String noScansFound = 'No scans found';
  static const String startScanning = 'Start Scanning';
}

/// Localization provider for internationalization
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  late final _strings = locale.languageCode == 'en' 
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
