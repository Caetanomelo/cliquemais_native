import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/br_input_formatters.dart';
import '../providers/app_state_provider.dart';

/// One-time-per-login-flow profile completion prompt, also reachable anytime
/// from Settings > "Meus dados" (same widget, only [cancelLabel] changes).
/// All fields are optional — [cancelLabel] is always available so the user
/// can bail without saving, matching the "completar depois" requirement.
Future<void> showProfileCompletionDialog(
  BuildContext context, {
  String cancelLabel = 'Completar depois',
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.borderDark),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: _ProfileCompletionForm(cancelLabel: cancelLabel),
    ),
  );
}

class _ProfileCompletionForm extends StatefulWidget {
  final String cancelLabel;
  const _ProfileCompletionForm({required this.cancelLabel});

  @override
  State<_ProfileCompletionForm> createState() => _ProfileCompletionFormState();
}

class _ProfileCompletionFormState extends State<_ProfileCompletionForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  XFile? _pickedAvatar;
  String? _existingAvatarUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppStateProvider>().auth.currentUser;
    final displayName = user?.userMetadata?['display_name'];
    if (displayName is String) _nameCtrl.text = displayName;
    _emailCtrl.text = user?.email ?? '';
    _loadExistingProfile();
  }

  /// Pre-fills already-saved fields (phone/cpf/address/avatar) so reopening
  /// this dialog -- from the post-login flow a second time, or from Settings
  /// > "Meus dados" -- doesn't wipe out what the user filled in before.
  /// Mirrors ProfilePage.open() in WEB_BASE's index.html, which does the
  /// same fetch-then-prefill before this dialog existed with this bug.
  Future<void> _loadExistingProfile() async {
    final auth = context.read<AppStateProvider>().auth;
    final profile = await auth.getProfile();
    if (!mounted || profile == null) return;
    setState(() {
      final phone = profile['phone'];
      if (phone is String && phone.isNotEmpty) _phoneCtrl.text = phone;
      final cpf = profile['cpf'];
      if (cpf is String && cpf.isNotEmpty) _cpfCtrl.text = cpf;
      final address = profile['address'];
      if (address is String && address.isNotEmpty) _addressCtrl.text = address;
      final avatarUrl = profile['avatar_url'];
      if (avatarUrl is String && avatarUrl.isNotEmpty) _existingAvatarUrl = avatarUrl;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  File _pickedAvatarAsFile() => File(_pickedAvatar!.path);

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) setState(() => _pickedAvatar = picked);
  }

  Future<void> _save() async {
    if (_cpfCtrl.text.isNotEmpty && !isValidCpf(_cpfCtrl.text)) {
      setState(() => _error = 'CPF inválido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AppStateProvider>().auth;
    try {
      String? avatarUrl;
      final picked = _pickedAvatar;
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
        avatarUrl = await auth.uploadAvatar(bytes, fileExt: ext);
      }
      await auth.updateProfile(
        fullName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        cpf: _cpfCtrl.text.trim().isEmpty ? null : _cpfCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        avatarUrl: avatarUrl,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Saving is optional data — a failure must not trap the user here.
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar agora. Tente de novo ou complete depois.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Complete seu cadastro',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMainDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Esses dados são opcionais e ajudam a personalizar sua experiência.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark, height: 1.4),
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppTheme.surfaceDark,
                      backgroundImage: _pickedAvatar != null
                          ? FileImage(_pickedAvatarAsFile())
                          : (_existingAvatarUrl != null ? NetworkImage(_existingAvatarUrl!) : null) as ImageProvider?,
                      child: _pickedAvatar == null && _existingAvatarUrl == null
                          ? const Icon(Icons.person_rounded, size: 42, color: AppTheme.textSubDark)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          gradient: AppTheme.primaryButtonGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FieldLabel('Nome completo'),
            _CompletionField(controller: _nameCtrl, hint: 'Seu nome completo', keyboardType: TextInputType.name),
            const SizedBox(height: 12),
            _FieldLabel('E-mail'),
            _CompletionField(controller: _emailCtrl, hint: 'E-mail', enabled: false),
            const SizedBox(height: 12),
            _FieldLabel('Celular'),
            _CompletionField(
              controller: _phoneCtrl,
              hint: '(00) 00000-0000',
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
            ),
            const SizedBox(height: 12),
            _FieldLabel('CPF'),
            _CompletionField(
              controller: _cpfCtrl,
              hint: '000.000.000-00',
              keyboardType: TextInputType.number,
              inputFormatters: [CpfInputFormatter()],
            ),
            const SizedBox(height: 12),
            _FieldLabel('Endereço'),
            _CompletionField(controller: _addressCtrl, hint: 'Rua, número, bairro, cidade', maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.red)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(widget.cancelLabel, style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textSubDark)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSubDark),
      ),
    );
  }
}

class _CompletionField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  const _CompletionField({
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(
        fontFamily: 'Sora',
        fontSize: 14,
        color: enabled ? AppTheme.textMainDark : AppTheme.textSubDark,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: enabled ? 0.05 : 0.02),
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSubDark),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          borderSide: const BorderSide(color: AppTheme.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          borderSide: const BorderSide(color: AppTheme.borderDark),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          borderSide: BorderSide(color: AppTheme.borderDark.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          borderSide: const BorderSide(color: AppTheme.accentBright),
        ),
      ),
    );
  }
}
