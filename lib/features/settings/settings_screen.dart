import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/sms/sms_service.dart';
import '../../shared/providers/household_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl   = TextEditingController();
  final _inviteCtrl = TextEditingController();
  bool _savingName  = false;
  bool _inviteSent  = false;
  bool? _smsEnabled;
  bool _smsToggling = false;

  @override
  void initState() {
    super.initState();
    _loadSmsEnabled();
  }

  Future<void> _loadSmsEnabled() async {
    final enabled = await SmsService.isEnabled();
    if (mounted) setState(() => _smsEnabled = enabled);
  }

  Future<void> _onSmsToggle(bool value) async {
    if (_smsToggling) return;
    setState(() => _smsToggling = true);
    try {
      if (value) {
        final granted = await SmsService.enable();
        if (!granted && mounted) {
          final permanentlyDenied = await Permission.sms.isPermanentlyDenied;
          if (permanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('SMS permission was denied. Tap to open Settings.'),
              action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
              behavior: SnackBarBehavior.floating,
            ));
          }
        }
      } else {
        await SmsService.disable();
      }
    } finally {
      await _loadSmsEnabled();
      if (mounted) setState(() => _smsToggling = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveHouseholdName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      final householdId = await ref.read(householdIdProvider.future);
      await Supabase.instance.client
          .from('households')
          .update({'name': name})
          .eq('id', householdId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Household name updated',
              style: GoogleFonts.plusJakartaSans()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _sendInvite() async {
    final email = _inviteCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) return;
    setState(() => _inviteSent = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite saved — $email will join when they sign up.',
            style: GoogleFonts.plusJakartaSans()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _inviteCtrl.clear();
      setState(() => _inviteSent = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('You will need to sign in again to access your budget.',
            style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Account info
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Signed in as',
                subtitle: user?.email ?? '—',
              ),
            ],
          ),
          const SizedBox(height: 24),

          _sectionLabel(context, 'HOUSEHOLD'),
          const SizedBox(height: 8),
          _SettingsCard(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Household name',
                        prefixIcon: Icon(Icons.home_outlined, size: 18),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveHouseholdName(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _savingName ? null : _saveHouseholdName,
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                    child: _savingName
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Save',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inviteCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Invite partner',
                        hintText: 'partner@email.com',
                        prefixIcon: Icon(Icons.person_add_outlined, size: 18),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendInvite(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _inviteSent ? null : _sendInvite,
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                    child: Text('Invite',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          _sectionLabel(context, 'FEATURES'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.sms_outlined, size: 20, color: cs.onSurfaceVariant),
                title: Text('Bank SMS detection',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text(
                  'Auto-detect transactions from bank SMS',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
                value: _smsEnabled ?? false,
                onChanged: _smsToggling || _smsEnabled == null ? null : _onSmsToggle,
                activeThumbColor: cs.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.logout, color: cs.error, size: 20),
                title: Text('Sign out',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.error)),
                onTap: _signOut,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  const _SettingsCard({required this.children, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: padding,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SettingsTile(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      title: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: cs.onSurfaceVariant)),
      subtitle: Text(subtitle,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
