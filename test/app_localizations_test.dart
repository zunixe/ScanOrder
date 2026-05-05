import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  group('AppLocalizations', () {
    test('Indonesian strings are correct', () {
      final l10n = AppLocalizations(const Locale('id'));
      expect(l10n.appName, 'ScanOrder');
      expect(l10n.scanHistory, 'Riwayat Scan');
      expect(l10n.searchResi, 'Cari nomor resi...');
      expect(l10n.scanResi, 'Scan resi');
      expect(l10n.allDates, 'Semua');
      expect(l10n.scans, 'scan');
      expect(l10n.cancel, 'Batal');
      expect(l10n.confirm, 'Konfirmasi');
      expect(l10n.delete, 'Hapus');
      expect(l10n.settings, 'Pengaturan');
      expect(l10n.login, 'Login');
      expect(l10n.logout, 'Logout');
      expect(l10n.loading, 'Memuat...');
      expect(l10n.error, 'Terjadi kesalahan');
      expect(l10n.retry, 'Coba Lagi');
      expect(l10n.noScansFound, 'Tidak ada scan ditemukan');
      expect(l10n.startScanning, 'Mulai Scan');
      expect(l10n.freeTier, 'Gratis');
      expect(l10n.proTier, 'Pro');
      expect(l10n.teamTier, 'Tim');
    });

    test('English strings are correct', () {
      final l10n = AppLocalizations(const Locale('en'));
      expect(l10n.appName, 'ScanOrder');
      expect(l10n.scanHistory, 'Scan History');
      expect(l10n.searchResi, 'Search tracking number...');
      expect(l10n.scanResi, 'Scan tracking');
      expect(l10n.allDates, 'All');
      expect(l10n.scans, 'scans');
      expect(l10n.cancel, 'Cancel');
      expect(l10n.confirm, 'Confirm');
      expect(l10n.delete, 'Delete');
      expect(l10n.settings, 'Settings');
      expect(l10n.login, 'Login');
      expect(l10n.logout, 'Logout');
      expect(l10n.loading, 'Loading...');
      expect(l10n.error, 'An error occurred');
      expect(l10n.retry, 'Retry');
      expect(l10n.noScansFound, 'No scans found');
      expect(l10n.startScanning, 'Start Scanning');
      expect(l10n.freeTier, 'Free');
      expect(l10n.proTier, 'Pro');
      expect(l10n.teamTier, 'Team');
    });

    test('unknown locale defaults to Indonesian', () {
      final l10n = AppLocalizations(const Locale('fr'));
      // Should fall back to Indonesian (default)
      expect(l10n.scanHistory, 'Riwayat Scan');
      expect(l10n.cancel, 'Batal');
    });

    test('all getters return non-empty strings for Indonesian', () {
      final l10n = AppLocalizations(const Locale('id'));
      expect(l10n.appName, isNotEmpty);
      expect(l10n.scanHistory, isNotEmpty);
      expect(l10n.searchResi, isNotEmpty);
      expect(l10n.scanResi, isNotEmpty);
      expect(l10n.allDates, isNotEmpty);
      expect(l10n.scans, isNotEmpty);
      expect(l10n.exportCsv, isNotEmpty);
      expect(l10n.exportXlsx, isNotEmpty);
      expect(l10n.dataSavedLocally, isNotEmpty);
      expect(l10n.loginForBackup, isNotEmpty);
      expect(l10n.login, isNotEmpty);
      expect(l10n.category, isNotEmpty);
      expect(l10n.marketplace, isNotEmpty);
      expect(l10n.date, isNotEmpty);
      expect(l10n.time, isNotEmpty);
      expect(l10n.delete, isNotEmpty);
      expect(l10n.cancel, isNotEmpty);
      expect(l10n.confirm, isNotEmpty);
      expect(l10n.deleteConfirm, isNotEmpty);
      expect(l10n.stats, isNotEmpty);
      expect(l10n.totalScans, isNotEmpty);
      expect(l10n.todayScans, isNotEmpty);
      expect(l10n.thisWeekScans, isNotEmpty);
      expect(l10n.settings, isNotEmpty);
      expect(l10n.subscription, isNotEmpty);
      expect(l10n.about, isNotEmpty);
      expect(l10n.version, isNotEmpty);
      expect(l10n.loading, isNotEmpty);
      expect(l10n.error, isNotEmpty);
      expect(l10n.retry, isNotEmpty);
      expect(l10n.noScansFound, isNotEmpty);
      expect(l10n.startScanning, isNotEmpty);
    });
  });

  group('AppStrings abstract class', () {
    test('AppStringsId extends AppStrings', () {
      expect(AppStringsId() is AppStrings, isTrue);
    });

    test('AppStringsEn extends AppStrings', () {
      expect(AppStringsEn() is AppStrings, isTrue);
    });
  });
}
