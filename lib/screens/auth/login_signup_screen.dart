import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/br_input_formatters.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/profile_completion_dialog.dart';
import '../dashboard/dashboard_screen.dart';

/// Mandatory login/signup gate reached after [HeroScreen]'s loading bar —
/// there is no way to reach [DashboardScreen] without going through here
/// first. Only e-mail/senha is functional today; telefone/Google/Apple/
/// Facebook render as visible "em breve" options (no credentials configured
/// for any of them yet) so the full intended auth surface is in place
/// without pretending it already works.
class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

enum _ContactMode { email, phone }

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  bool _signupMode = false;
  _ContactMode _contactMode = _ContactMode.email;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;
  String? _cpfError;
  String? _phoneError;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(Object err) {
    final msg = err.toString().toLowerCase();
    if (msg.contains('already registered'))
      return 'Este e-mail já tem conta — tente entrar.';
    if (msg.contains('invalid login')) return 'E-mail ou senha incorretos.';
    if (msg.contains('password') && msg.contains('least'))
      return 'Senha muito curta (mínimo 6 caracteres).';
    if (msg.contains('supabase-not-configured'))
      return 'Login indisponível no momento. Tente novamente mais tarde.';
    if (msg.contains('profiles_cpf_unique'))
      return 'Este CPF já está cadastrado.';
    if (msg.contains('profiles_phone_unique'))
      return 'Este telefone já está cadastrado.';
    if (msg.contains('rate limit'))
      return 'Muitos cadastros em pouco tempo — aguarde alguns minutos e tente novamente.';
    if (msg.contains('email address') && msg.contains('invalid'))
      return 'E-mail inválido — confira e tente de novo.';
    if (msg.contains('check_contact_available') ||
        (msg.contains('function') && msg.contains('does not exist'))) {
      return 'Cadastro temporariamente indisponível — tente novamente em instantes.';
    }
    return 'Não foi possível concluir. Tente novamente.';
  }

  void _clearErrors() {
    _error = null;
    _cpfError = null;
    _phoneError = null;
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _clearErrors();
        _error = 'Preencha e-mail e senha.';
      });
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final cpf = _cpfCtrl.text.trim();
    if (_signupMode) {
      if (name.isEmpty || phone.isEmpty || cpf.isEmpty) {
        setState(() {
          _clearErrors();
          _error = 'Preencha nome, telefone e CPF.';
        });
        return;
      }
      if (!isValidCpf(cpf)) {
        setState(() {
          _clearErrors();
          _error = 'CPF inválido.';
        });
        return;
      }
    }
    setState(() {
      _submitting = true;
      _clearErrors();
    });
    final app = context.read<AppStateProvider>();
    try {
      if (_signupMode) {
        final avail = await app.auth.checkContactAvailable(
          cpf: cpf,
          phone: phone,
        );
        if (avail.cpfTaken) {
          setState(() => _cpfError = 'Este CPF já está cadastrado.');
          return;
        }
        if (avail.phoneTaken) {
          setState(() => _phoneError = 'Este telefone já está cadastrado.');
          return;
        }
        await app.auth.signUp(email, password, displayName: name);
        await app.auth.updateProfile(phone: phone, cpf: cpf);
      } else {
        await app.auth.signIn(email, password);
      }
      if (!mounted) return;
      final profile = await app.auth.getProfile();
      if (!mounted) return;
      final alreadyPrompted =
          profile != null && profile['profile_prompt_seen'] == true;
      if (!alreadyPrompted) {
        await showProfileCompletionDialog(context);
        if (mounted) await app.auth.markProfilePromptSeen();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      // A raw Postgres unique-violation surfaces here as a fallback path --
      // the primary path is checkContactAvailable() above, which already
      // routes to the field error before this ever runs.
      if (msg.contains('profiles_cpf_unique')) {
        setState(() => _cpfError = 'Este CPF já está cadastrado.');
      } else if (msg.contains('profiles_phone_unique')) {
        setState(() => _phoneError = 'Este telefone já está cadastrado.');
      } else {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDashboard,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Entre para continuar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMainDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sua conta salva o progresso de cada frase e palavra e sincroniza entre o app e o site.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    color: AppTheme.textSubDark,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  decoration: AppTheme.glassCard(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ModeTab(
                              label: 'Entrar',
                              active: !_signupMode,
                              onTap: () => setState(() {
                                _signupMode = false;
                                _clearErrors();
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _ModeTab(
                              label: 'Criar conta',
                              active: _signupMode,
                              onTap: () => setState(() {
                                _signupMode = true;
                                _clearErrors();
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _ModeTab(
                              label: 'E-mail',
                              active: _contactMode == _ContactMode.email,
                              onTap: () => setState(() {
                                _contactMode = _ContactMode.email;
                                _clearErrors();
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _ModeTab(
                              label: 'Telefone',
                              active: _contactMode == _ContactMode.phone,
                              onTap: () => setState(() {
                                _contactMode = _ContactMode.phone;
                                _clearErrors();
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_contactMode == _ContactMode.email) ...[
                        if (_signupMode) ...[
                          _AuthField(
                            controller: _nameCtrl,
                            label: 'Nome completo',
                            hint: 'Seu nome',
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 10),
                          _AuthField(
                            controller: _phoneCtrl,
                            label: 'Celular',
                            hint: '(00) 00000-0000',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [PhoneInputFormatter()],
                            errorText: _phoneError,
                          ),
                          const SizedBox(height: 10),
                          _AuthField(
                            controller: _cpfCtrl,
                            label: 'CPF',
                            hint: '000.000.000-00',
                            keyboardType: TextInputType.number,
                            inputFormatters: [CpfInputFormatter()],
                            errorText: _cpfError,
                          ),
                          const SizedBox(height: 10),
                        ],
                        _AuthField(
                          controller: _emailCtrl,
                          label: 'E-mail',
                          hint: 'voce@email.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 10),
                        _AuthField(
                          controller: _passwordCtrl,
                          label: 'Senha',
                          hint: 'Senha',
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: _obscurePassword
                                  ? AppTheme.textSubDark
                                  : AppTheme.accentBright,
                              size: 20,
                            ),
                            tooltip: _obscurePassword
                                ? 'Mostrar senha'
                                : 'Ocultar senha',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 12,
                              color: AppTheme.red,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_signupMode ? 'Criar conta' : 'Entrar'),
                        ),
                      ] else ...[
                        _AuthField(
                          controller: _phoneCtrl,
                          label: 'Celular',
                          hint: '(00) 00000-0000',
                          keyboardType: TextInputType.phone,
                          inputFormatters: [PhoneInputFormatter()],
                          errorText: _phoneError,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => showComingSoonSnackbar(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.borderDark),
                            foregroundColor: AppTheme.textSubDark,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Enviar código'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: const [
                    Expanded(child: Divider(color: AppTheme.borderDark)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'ou continue com',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 11,
                          color: AppTheme.textSubDark,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppTheme.borderDark)),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    _SocialAuthButton(
                      icon: Icons.g_mobiledata_rounded,
                      label: 'Google',
                    ),
                    SizedBox(width: 12),
                    _SocialAuthButton(
                      icon: Icons.apple_rounded,
                      label: 'Apple',
                    ),
                    SizedBox(width: 12),
                    _SocialAuthButton(
                      icon: Icons.facebook_rounded,
                      label: 'Facebook',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SocialAuthButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: 0.55,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              button: true,
              enabled: false,
              label: '$label — em breve',
              child: OutlinedButton(
                onPressed: () => showComingSoonSnackbar(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.borderDark),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Icon(icon, color: AppTheme.textSubDark),
              ),
            ),
            Positioned(
              top: -8,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'EM BREVE',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accentBright.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: active
                ? AppTheme.accentBright.withValues(alpha: 0.4)
                : AppTheme.borderDark,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? AppTheme.accentBright : AppTheme.textSubDark,
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final String? errorText;
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.suffixIcon,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSubDark,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 14,
            color: AppTheme.textMainDark,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textSubDark),
            suffixIcon: suffixIcon,
            errorText: errorText,
            errorStyle: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 11,
              color: AppTheme.red,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: const BorderSide(color: AppTheme.borderDark),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: const BorderSide(color: AppTheme.borderDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: const BorderSide(color: AppTheme.accentBright),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: const BorderSide(color: AppTheme.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: const BorderSide(color: AppTheme.red),
            ),
          ),
        ),
      ],
    );
  }
}
