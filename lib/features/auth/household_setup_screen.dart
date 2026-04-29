import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';

class HouseholdSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreated;
  const HouseholdSetupScreen({super.key, this.onCreated});

  @override
  ConsumerState<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  final _nameCtrl    = TextEditingController(text: 'Our Budget');
  final _inviteCtrl  = TextEditingController();
  final _formKey     = GlobalKey<FormState>();

  bool _loading = false;
  bool _done    = false;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    try {
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final res = await client
          .from('household_members')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      if ((res as List).isNotEmpty && mounted) {
        widget.onCreated?.call();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser!.id;

      // bootstrap_household creates the household, adds owner, and seeds default categories
      await client.rpc<String>('bootstrap_household', params: {
        'p_user_id':        userId,
        'p_household_name': _nameCtrl.text.trim(),
      });

      // Optionally invite spouse
      final inviteEmail = _inviteCtrl.text.trim();
      if (inviteEmail.isNotEmpty) {
        await _sendInvite(client, inviteEmail);
      }

      setState(() => _done = true);
      widget.onCreated?.call();
    } on PostgrestException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Could not create household. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendInvite(SupabaseClient client, String email) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Invite saved — $email will join when they sign up.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.plusJakartaSans()),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);

    if (_done) {
      return _SuccessView(onContinue: () {
        // Router redirect will pick up the household and navigate to /budget
      });
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: size.width > 480 ? (size.width - 440) / 2 : 24,
              vertical: 32,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Center(
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(Icons.home_outlined, size: 36, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Set up your household',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your household is a shared budget space.\nYou and your partner see the same data.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Household name
                  TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    style: GoogleFonts.plusJakartaSans(color: cs.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Household name',
                      prefixIcon: Icon(Icons.edit_outlined),
                      hintText: 'e.g. "Our Budget" or "Smith Family"',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Invite partner
                  TextFormField(
                    controller: _inviteCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _create(),
                    style: GoogleFonts.plusJakartaSans(color: cs.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Invite partner (optional)',
                      prefixIcon: Icon(Icons.person_add_outlined),
                      hintText: 'partner@email.com',
                    ),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You can always invite them later from Settings.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),

                  FilledButton(
                    onPressed: _loading ? null : _create,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                          )
                        : Text(
                            'Create Household',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15, fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final VoidCallback onContinue;
  const _SuccessView({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 40, color: cs.tertiary),
              ),
              const SizedBox(height: 24),
              Text(
                'Household created!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Taking you to your budget…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
