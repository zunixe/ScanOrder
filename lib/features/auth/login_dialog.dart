import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/quota_service.dart';
import 'auth_provider.dart';

void showLoginDialog(BuildContext context, {VoidCallback? onSuccess}) {
  showDialog(
    context: context,
    builder: (ctx) => _LoginDialogContent(onSuccess: onSuccess),
  );
}

class _LoginDialogContent extends StatefulWidget {
  final VoidCallback? onSuccess;
  const _LoginDialogContent({this.onSuccess});

  @override
  State<_LoginDialogContent> createState() => _LoginDialogContentState();
}

class _LoginDialogContentState extends State<_LoginDialogContent> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isSignup = false;
  bool _hasClosed = false;
  StorageTier _selectedTier = StorageTier.basic;

  @override
  void initState() {
    super.initState();
    // Auto-close dialog saat Google OAuth berhasil (authStateChanges trigger)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      auth.addListener(_onAuthChange);
    });
  }

  void _onAuthChange() {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn) {
      _closeAfterLogin();
    }
  }

  void _closeAfterLogin() {
    if (!mounted || _hasClosed) return;
    _hasClosed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
      widget.onSuccess?.call();
    });
  }

  @override
  void dispose() {
    try { context.read<AuthProvider>().removeListener(_onAuthChange); } catch (_) {}
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Consumer<AuthProvider>(
        builder: (_, auth, _) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isSignup ? 'Buat Akun' : 'Login ke Cloud',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => auth.clearError(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => auth.clearError(),
                    ),
                    if (_isSignup) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Pilih Paket',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _TierChip(
                            label: 'Basic',
                            subtitle: '1rb scan',
                            selected: _selectedTier == StorageTier.basic,
                            color: Colors.blue,
                            onTap: () => setState(() => _selectedTier = StorageTier.basic),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _TierChip(
                            label: 'Pro',
                            subtitle: '5rb scan',
                            selected: _selectedTier == StorageTier.pro,
                            color: AppTheme.primaryColor,
                            onTap: () => setState(() => _selectedTier = StorageTier.pro),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _TierChip(
                            label: 'Team',
                            subtitle: '∞ scan',
                            selected: _selectedTier == StorageTier.unlimited,
                            color: Colors.deepPurple,
                            onTap: () => setState(() => _selectedTier = StorageTier.unlimited),
                          )),
                        ],
                      ),
                    ],
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withAlpha(50)),
                        ),
                        child: Text(
                          _formatError(auth.error!),
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: auth.isLoading
                          ? null
                          : () async {
                              final email = _emailCtrl.text.trim();
                              final pass = _passCtrl.text;
                              if (_isSignup) {
                                await auth.signUp(email, pass, tier: _selectedTier);
                              } else {
                                await auth.signIn(email, pass);
                              }
                              if (auth.error == null && auth.isLoggedIn) {
                                _closeAfterLogin();
                              }
                            },
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isSignup ? 'Daftar' : 'Login'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isSignup = !_isSignup),
                      child: Text(_isSignup ? 'Sudah punya akun? Login' : 'Belum punya akun? Daftar'),
                    ),
                    const Divider(),
                    OutlinedButton.icon(
                      onPressed: auth.isLoading ? null : () => auth.signInWithGoogle(),
                      icon: const Icon(Icons.login),
                      label: const Text('Login dengan Google'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatError(String raw) {
    if (raw.contains('email_not_confirmed')) {
      return 'Email belum dikonfirmasi.\nCek inbox/spam atau matikan "Confirm email" di Supabase.';
    }
    if (raw.contains('invalid_credentials')) {
      return 'Email atau password salah.';
    }
    if (raw.contains('user_not_found')) {
      return 'Akun tidak ditemukan. Silakan daftar.';
    }
    return raw;
  }
}

class _TierChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TierChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(30) : Colors.grey.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.withAlpha(50),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? color : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: selected ? color : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
