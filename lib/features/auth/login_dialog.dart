import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Consumer<AuthProvider>(
        builder: (_, auth, __) {
          if (auth.isLoggedIn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pop(context);
              widget.onSuccess?.call();
            });
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isSignup ? 'Buat Akun' : 'Login ke Cloud',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                if (auth.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: auth.isLoading
                        ? null
                        : () {
                            final email = _emailCtrl.text.trim();
                            final pass = _passCtrl.text;
                            if (_isSignup) {
                              auth.signUp(email, pass);
                            } else {
                              auth.signIn(email, pass);
                            }
                          },
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isSignup ? 'Daftar' : 'Login'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isSignup = !_isSignup),
                  child: Text(_isSignup ? 'Sudah punya akun? Login' : 'Belum punya akun? Daftar'),
                ),
                const Divider(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: auth.isLoading ? null : () => auth.signInWithGoogle(),
                    icon: const Icon(Icons.login),
                    label: const Text('Login dengan Google'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
