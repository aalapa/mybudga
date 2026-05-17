import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/sms/sms_service.dart';
import '../../core/theme/theme_provider.dart';
import '../../shared/models/account.dart';
import '../../shared/models/scheduled_transaction.dart';
import '../../shared/providers/categories_provider.dart';
import '../../shared/providers/household_provider.dart';
import '../../shared/providers/payees_provider.dart';
import '../accounts/accounts_provider.dart';
import '../auth/app_lock_provider.dart';
import '../auth/app_lock_screen.dart';
import '../budget/budget_provider.dart';
import '../cashflow/cashflow_provider.dart';
import '../cashflow/cashflow_screen.dart';
import '../transactions/transactions_provider.dart';
import 'ynab_import_service.dart';

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
  bool _resetting         = false;
  bool _resettingAccounts = false;
  bool _exporting         = false;

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

  // ---------------------------------------------------------------------------
  // Import from YNAB
  // ---------------------------------------------------------------------------

  Future<void> _importFromYnab() async {
    if (!mounted) return;
    final householdId = await ref.read(householdIdProvider.future);
    if (!mounted) return;
    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _YnabImportSheet(
        householdId: householdId,
        onImported:  () {
          ref.invalidate(accountsProvider);
          ref.invalidate(budgetProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(payeesProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(cashflowProvider);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Reset accounts & transactions (preserve budget plan)
  // ---------------------------------------------------------------------------

  Future<void> _resetAccountsAndTransactions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Reset accounts & transactions?',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This will permanently delete:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final item in [
                'All accounts',
                'All transactions',
                'Scheduled transactions',
                'Payees',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(Icons.remove_circle_outline,
                        size: 14, color: cs.error),
                    const SizedBox(width: 6),
                    Text(item,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                  ]),
                ),
              const SizedBox(height: 12),
              Text('These will be kept:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final item in [
                'Category groups & categories',
                'Budget allocations (monthly plan)',
                'Goals',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: cs.tertiary),
                    const SizedBox(width: 6),
                    Text(item,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                  ]),
                ),
              const SizedBox(height: 10),
              Text('This cannot be undone.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear accounts & transactions'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingAccounts = true);
    try {
      final householdId = await ref.read(householdIdProvider.future);
      final client      = Supabase.instance.client;

      // 1. Clear self-referential transfer_id to avoid FK violation
      await client
          .from('transactions')
          .update({'transfer_id': null})
          .eq('household_id', householdId);

      // 2. Split transactions (best-effort — table/schema may differ)
      try {
        await client
            .from('split_transactions')
            .delete()
            .eq('household_id', householdId);
      } catch (_) {}

      // 3. Transactions, scheduled transactions, payees, accounts
      await client.from('transactions').delete().eq('household_id', householdId);
      try {
        await client.from('scheduled_transactions').delete().eq('household_id', householdId);
      } catch (_) {}
      await client.from('payees').delete().eq('household_id', householdId);
      await client.from('accounts').delete().eq('household_id', householdId);

      // Refresh affected providers — categories/budget plan untouched
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(budgetProvider);
      ref.invalidate(cashflowProvider);
      ref.invalidate(payeesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Accounts and transactions cleared. '
              'Your budget plan is intact.',
              style: GoogleFonts.plusJakartaSans()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset failed: $e',
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _resettingAccounts = false);
    }
  }

  // Reset budget
  // ---------------------------------------------------------------------------

  Future<void> _resetBudget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset budget?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text(
          'This will permanently delete everything — all accounts, transactions, '
          'categories, budget allocations, payees, and scheduled transactions.\n\n'
          'This cannot be undone.',
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      final householdId = await ref.read(householdIdProvider.future);
      final client      = Supabase.instance.client;

      // 1. Remove self-referential transfer_id to avoid FK violation
      await client.from('transactions')
          .update({'transfer_id': null})
          .eq('household_id', householdId);

      // 2. Delete split_transactions (best-effort — table/schema may differ)
      try {
        await client.from('split_transactions')
            .delete()
            .eq('household_id', householdId);
      } catch (_) {}

      // 3-9. Delete in FK-safe order
      await client.from('transactions').delete().eq('household_id', householdId);
      try {
        await client.from('scheduled_transactions').delete().eq('household_id', householdId);
      } catch (_) {}
      await client.from('budget_months').delete().eq('household_id', householdId);
      await client.from('category_goals').delete().eq('household_id', householdId);
      await client.from('payees').delete().eq('household_id', householdId);
      // Deleting categories sets accounts.cc_payment_category_id = NULL (ON DELETE SET NULL)
      await client.from('categories').delete().eq('household_id', householdId);
      await client.from('category_groups').delete().eq('household_id', householdId);
      await client.from('accounts').delete().eq('household_id', householdId);

      // Invalidate all providers so UI refreshes
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(budgetProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(payeesProvider);
      ref.invalidate(cashflowProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Budget reset complete.',
              style: GoogleFonts.plusJakartaSans()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset failed: $e',
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Export backup
  // ---------------------------------------------------------------------------

  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    try {
      final householdId = await ref.read(householdIdProvider.future);
      final client      = Supabase.instance.client;

      final results = await Future.wait<dynamic>([
        client.from('households').select().eq('id', householdId).single(),
        client.from('accounts').select().eq('household_id', householdId),
        client.from('category_groups').select().eq('household_id', householdId),
        client.from('categories').select().eq('household_id', householdId),
        client.from('category_goals').select().eq('household_id', householdId),
        client.from('budget_months').select().eq('household_id', householdId),
        client.from('payees').select().eq('household_id', householdId),
        client.from('transactions')
            .select()
            .eq('household_id', householdId)
            .isFilter('deleted_at', null),
        client.from('scheduled_transactions').select().eq('household_id', householdId),
      ]);

      final backup = {
        'version':               1,
        'exported_at':           DateTime.now().toIso8601String(),
        'household':             results[0],
        'accounts':              results[1],
        'category_groups':       results[2],
        'categories':            results[3],
        'category_goals':        results[4],
        'budget_months':         results[5],
        'payees':                results[6],
        'transactions':          results[7],
        'scheduled_transactions': results[8],
      };

      final jsonStr  = const JsonEncoder.withIndent('  ').convert(backup);
      final dir      = await getTemporaryDirectory();
      final stamp    = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${dir.path}/mybudga_backup_$stamp.json';
      await File(filePath).writeAsString(jsonStr);

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/json')],
        subject: 'MyBudga Backup $stamp',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup failed: $e',
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

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
          // ── Appearance ─────────────────────────────────────────────────────
          _sectionLabel(context, 'APPEARANCE'),
          const SizedBox(height: 8),
          _AppearanceCard(),
          const SizedBox(height: 24),

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

          _sectionLabel(context, 'SECURITY'),
          const SizedBox(height: 8),
          _SecurityCard(),
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

          const _ScheduledSection(),
          const SizedBox(height: 24),

          _sectionLabel(context, 'AUTOMATION'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.rule_outlined, size: 20, color: cs.onSurfaceVariant),
                title: Text('Payee rules',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text('Auto-categorize transactions by payee',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _PayeeRulesSheet(widgetRef: ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _sectionLabel(context, 'DATA'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              ListTile(
                leading: _exporting
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.primary))
                    : Icon(Icons.download_outlined,
                        color: cs.primary, size: 20),
                title: Text('Export backup',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text('Save all data as JSON',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                onTap: _exporting ? null : _exportBackup,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16))),
              ),
              Divider(height: 1, indent: 52,
                  color: cs.outlineVariant.withValues(alpha: 0.4)),
              ListTile(
                leading: Icon(Icons.upload_file_outlined,
                    color: cs.tertiary, size: 20),
                title: Text('Import from YNAB',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text('Import accounts & transactions from YNAB CSV export',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                onTap: _importFromYnab,
              ),
              Divider(height: 1, indent: 52,
                  color: cs.outlineVariant.withValues(alpha: 0.4)),
              ListTile(
                leading: _resettingAccounts
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.error))
                    : Icon(Icons.account_balance_wallet_outlined,
                        color: cs.error, size: 20),
                title: Text('Reset accounts & transactions',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.error)),
                subtitle: Text(
                    'Clears accounts and transactions — keeps categories and budget plan',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                onTap: _resettingAccounts ? null : _resetAccountsAndTransactions,
              ),
              Divider(height: 1, indent: 52,
                  color: cs.outlineVariant.withValues(alpha: 0.4)),
              ListTile(
                leading: _resetting
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.error))
                    : Icon(Icons.restart_alt, color: cs.error, size: 20),
                title: Text('Reset everything',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.error)),
                subtitle: Text(
                    'Delete all accounts, transactions, categories & budgets',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                onTap: _resetting ? null : _resetBudget,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(16))),
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

// ---------------------------------------------------------------------------
// Appearance card — theme mode toggle + colour palette
// ---------------------------------------------------------------------------

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final settings = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Theme mode ────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.brightness_6_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Text('Theme',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon:  Icon(Icons.light_mode_outlined, size: 15),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon:  Icon(Icons.brightness_auto_outlined, size: 15),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon:  Icon(Icons.dark_mode_outlined, size: 15),
                    label: Text('Dark'),
                  ),
                ],
                selected:          {settings.mode},
                onSelectionChanged: (s) => notifier.setMode(s.first),
                style: ButtonStyle(
                  textStyle: WidgetStateProperty.all(
                      GoogleFonts.plusJakartaSans(fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),

            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── Accent colour ─────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.palette_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Text('Accent Colour',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing:    10,
              runSpacing: 10,
              children: [
                for (final entry in appColorPalette)
                  _ColorSwatch(
                    color:      entry.color,
                    label:      entry.label,
                    isSelected: settings.seedColor.toARGB32() ==
                        entry.color.toARGB32(),
                    onTap:      () => notifier.setSeedColor(entry.color),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single colour swatch circle ───────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width:  38,
          height: 38,
          decoration: BoxDecoration(
            color:  color,
            shape:  BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color:       color.withValues(alpha: 0.55),
                      blurRadius:  10,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scheduled transactions section
// ---------------------------------------------------------------------------

/// Returns the next occurrence date on or after today.
/// Normalises both sides to local midnight (date-only) so UTC-stored
/// nextDate values never compare as "before today" due to time components.
DateTime _nextUpcoming(ScheduledTransaction tx) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final raw   = tx.nextDate.toLocal();
  var d = DateTime(raw.year, raw.month, raw.day);
  while (d.isBefore(today)) {
    final next = tx.frequency.advance(d);
    if (next == null) return d; // 'once' — show as-is even if past
    d = DateTime(next.year, next.month, next.day);
  }
  return d;
}

class _ScheduledSection extends ConsumerWidget {
  const _ScheduledSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final cfAsync  = ref.watch(cashflowProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];

    final scheduled = [...(cfAsync.valueOrNull?.scheduled ?? [])]
      ..sort((a, b) => _nextUpcoming(a).compareTo(_nextUpcoming(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with Add button
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Text(
                'SCHEDULED TRANSACTIONS',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant, letterSpacing: 0.8),
              ),
              const Spacer(),
              InkWell(
                onTap: () => showAddScheduledSheet(context, ref),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text('Add',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: cs.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (cfAsync.isLoading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          ))
        else if (scheduled.isEmpty)
          _SettingsCard(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Text('No scheduled transactions',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: cs.onSurfaceVariant)),
              ]),
            ),
          ])
        else
          _SettingsCard(
            children: [
              for (int i = 0; i < scheduled.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 52,
                      color: cs.outlineVariant.withValues(alpha: 0.4)),
                _ScheduledTile(
                  tx:          scheduled[i],
                  nextDate:    _nextUpcoming(scheduled[i]),
                  accounts:    accounts,
                  isFirst:     i == 0,
                  isLast:      i == scheduled.length - 1,
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _ScheduledTile extends ConsumerWidget {
  final ScheduledTransaction tx;
  final DateTime nextDate;
  final List<Account> accounts;
  final bool isFirst;
  final bool isLast;

  const _ScheduledTile({
    required this.tx,
    required this.nextDate,
    required this.accounts,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d');

    final toAccount = tx.transferToAccountId != null
        ? accounts.where((a) => a.id == tx.transferToAccountId).firstOrNull
        : null;

    final title = tx.isTransfer
        ? 'Transfer${toAccount != null ? ' → ${toAccount.displayName}' : ''}'
        : (tx.payeeName?.isNotEmpty == true
            ? tx.payeeName!
            : (tx.memo ?? 'Unnamed'));

    final fromPart = tx.accountName != null ? ' · from ${tx.accountName}' : '';
    final subtitle = '${tx.frequency.label} · Next ${dateFmt.format(nextDate)}$fromPart';

    final isIncome   = !tx.isTransfer && tx.amount > 0;
    final isExpense  = !tx.isTransfer && tx.amount < 0;
    final iconColor  = tx.isTransfer
        ? cs.primary
        : (isIncome ? cs.tertiary : cs.error);
    final icon = tx.isTransfer
        ? Icons.swap_horiz_rounded
        : (isIncome
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded);

    final amountStr = tx.isTransfer
        ? fmt.format(tx.amount.abs())
        : (isExpense
            ? '-${fmt.format(tx.amount.abs())}'
            : '+${fmt.format(tx.amount)}');

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top:    isFirst ? const Radius.circular(16) : Radius.zero,
          bottom: isLast  ? const Radius.circular(16) : Radius.zero,
        ),
      ),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
      title: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      subtitle: Text(subtitle,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, color: cs.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(amountStr,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: iconColor)),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Delete scheduled transaction?',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Text('This cannot be undone.',
              style: GoogleFonts.plusJakartaSans()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(cashflowProvider.notifier).deleteScheduled(tx.id);
  }
}

// ---------------------------------------------------------------------------

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

// =============================================================================
// YNAB Import Sheet
// =============================================================================

class _YnabImportSheet extends StatefulWidget {
  final String householdId;
  final VoidCallback onImported;

  const _YnabImportSheet({
    required this.householdId,
    required this.onImported,
  });

  @override
  State<_YnabImportSheet> createState() => _YnabImportSheetState();
}

class _YnabImportSheetState extends State<_YnabImportSheet> {
  String? _registerPath;
  String? _registerContent;
  String? _budgetPath;
  String? _budgetContent;

  // Import from the last 12 months by default
  DateTime _fromDate = DateTime(
    DateTime.now().year - 1,
    DateTime.now().month,
    1,
  );

  YnabImportPreview? _preview;
  bool _importing  = false;
  String _stage    = '';
  double _progress = 0;
  YnabImportResult? _result;
  String? _error;

  // ---- file picking ----------------------------------------------------------

  Future<void> _pickRegister() async {
    final result = await FilePicker.platform.pickFiles(
      // FileType.any allows Google Drive / cloud files to be selected.
      // Extension filtering greys them out when they aren't cached locally.
      type:     FileType.any,
      withData: true,
    );
    if (result == null) return;
    final file    = result.files.single;
    final content = await _readFileContent(file);
    if (content == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read file — try downloading it to your device first.'),
        ));
      }
      return;
    }
    setState(() {
      _registerPath    = file.name;
      _registerContent = content;
      _preview         = null;
      _result          = null;
      _error           = null;
    });
    _updatePreview();
  }

  Future<void> _pickBudget() async {
    final result = await FilePicker.platform.pickFiles(
      type:     FileType.any,
      withData: true,
    );
    if (result == null) return;
    final file    = result.files.single;
    final content = await _readFileContent(file);
    if (content == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read file — try downloading it to your device first.'),
        ));
      }
      return;
    }
    setState(() {
      _budgetPath    = file.name;
      _budgetContent = content;
      _result        = null;
      _error         = null;
    });
  }

  /// Read content from a picked file — prefers in-memory bytes, falls back to path.
  Future<String?> _readFileContent(PlatformFile file) async {
    // bytes are set when withData: true and the file is locally available
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return String.fromCharCodes(file.bytes!);
    }
    // path fallback for local files on Android / iOS
    if (file.path != null) {
      try {
        return await File(file.path!).readAsString();
      } catch (_) {}
    }
    return null;
  }

  void _updatePreview() {
    if (_registerContent == null) return;
    try {
      final p = YnabImportService.preview(
        registerCsv: _registerContent!,
        fromDate:    _fromDate,
      );
      setState(() => _preview = p);
    } catch (e) {
      setState(() => _error = 'Could not parse CSV: $e');
    }
  }

  // ---- date picker -----------------------------------------------------------

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _fromDate,
      firstDate:   DateTime(2015),
      lastDate:    DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _fromDate = DateTime(picked.year, picked.month, 1);
      _preview  = null;
    });
    _updatePreview();
  }

  // ---- import ----------------------------------------------------------------

  Future<void> _runImport() async {
    if (_registerContent == null) return;
    setState(() {
      _importing = true;
      _stage     = 'Starting…';
      _progress  = 0;
      _error     = null;
      _result    = null;
    });

    try {
      final service = YnabImportService(
        client:      Supabase.instance.client,
        householdId: widget.householdId,
      );

      final result = await service.import(
        registerCsv: _registerContent!,
        budgetCsv:   _budgetContent,
        fromDate:    _fromDate,
        onProgress:  (stage, p) {
          if (mounted) setState(() { _stage = stage; _progress = p; });
        },
      );

      setState(() {
        _result    = result;
        _importing = false;
      });
      widget.onImported();
    } catch (e) {
      setState(() {
        _error     = e.toString();
        _importing = false;
      });
    }
  }

  // ---- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, yyyy');

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.upload_file_outlined, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('Import from YNAB',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: cs.onSurface)),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                    20, 4, 20,
                    MediaQuery.of(context).viewInsets.bottom + 24),
                children: [

                  // Info banner
                  if (_result == null && !_importing) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'In YNAB → Export Data → choose "All Data" to get the Register and Budget CSV files.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // SUCCESS
                  if (_result != null) ...[
                    _ResultBanner(result: _result!),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Done',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]

                  // IMPORTING
                  else if (_importing) ...[
                    const SizedBox(height: 24),
                    LinearProgressIndicator(value: _progress,
                        borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 12),
                    Text(_stage,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  ]

                  // CONFIGURE
                  else ...[

                    // ── Register CSV ──────────────────────────────────
                    _SectionLabel('Register CSV (required)'),
                    const SizedBox(height: 6),
                    _FileTile(
                      label:    _registerPath ?? 'No file selected',
                      picked:   _registerPath != null,
                      onTap:    _pickRegister,
                      buttonLabel: _registerPath != null ? 'Change' : 'Pick file',
                    ),
                    const SizedBox(height: 16),

                    // ── Budget CSV ────────────────────────────────────
                    _SectionLabel('Budget CSV (optional — imports current month allocations)'),
                    const SizedBox(height: 6),
                    _FileTile(
                      label:    _budgetPath ?? 'No file selected',
                      picked:   _budgetPath != null,
                      onTap:    _pickBudget,
                      buttonLabel: _budgetPath != null ? 'Change' : 'Pick file',
                    ),
                    const SizedBox(height: 16),

                    // ── Date filter ───────────────────────────────────
                    _SectionLabel('Import transactions from'),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap:         _pickFromDate,
                      borderRadius:  BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 16, color: cs.primary),
                            const SizedBox(width: 10),
                            Text(fmt.format(_fromDate),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14, fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            const Spacer(),
                            Icon(Icons.chevron_right,
                                size: 18, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Preview ───────────────────────────────────────
                    if (_preview != null) ...[
                      _PreviewCard(preview: _preview!),
                      const SizedBox(height: 20),
                    ],

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, color: cs.onErrorContainer)),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Import button ─────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _registerContent == null ? null : _runImport,
                        icon:  const Icon(Icons.upload_rounded, size: 18),
                        label: Text('Import',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (_registerContent == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Pick the Register CSV to continue',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.6),
      );
}

class _FileTile extends StatelessWidget {
  final String label;
  final bool picked;
  final VoidCallback onTap;
  final String buttonLabel;

  const _FileTile({
    required this.label,
    required this.picked,
    required this.onTap,
    required this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: picked
            ? Border.all(color: cs.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            picked ? Icons.check_circle_outline : Icons.insert_drive_file_outlined,
            size: 18,
            color: picked ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: picked ? cs.onSurface : cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
                minimumSize: const Size(72, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Text(buttonLabel,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final YnabImportPreview preview;
  const _PreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cs.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant, letterSpacing: 0.6)),
          const SizedBox(height: 10),
          Row(
            children: [
              _PreviewStat(icon: Icons.account_balance_outlined,
                  value: '${preview.accounts}', label: 'Accounts'),
              const SizedBox(width: 12),
              _PreviewStat(icon: Icons.category_outlined,
                  value: '${preview.categories}', label: 'Categories'),
              const SizedBox(width: 12),
              _PreviewStat(icon: Icons.receipt_long_outlined,
                  value: '${preview.transactions}', label: 'Transactions'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _PreviewStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final YnabImportResult result;
  const _ResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: cs.tertiary, size: 20),
              const SizedBox(width: 8),
              Text('Import complete!',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          _ResultRow('Accounts',      '${result.accounts}'),
          _ResultRow('Categories',    '${result.categories}'),
          _ResultRow('Payees',        '${result.payees}'),
          _ResultRow('Transactions',  '${result.transactions}'),
          if (result.budgetEntries > 0)
            _ResultRow('Budget entries', '${result.budgetEntries}'),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${result.warnings.length} warning(s)',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: cs.onSurfaceVariant)),
          Text(value, style: GoogleFonts.plusJakartaSans(
              fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payee Rules sheet
// ---------------------------------------------------------------------------

class _PayeeRulesSheet extends ConsumerWidget {
  final WidgetRef widgetRef;
  const _PayeeRulesSheet({required this.widgetRef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs      = Theme.of(context).colorScheme;
    final payees  = ref.watch(payeesProvider);
    final catGroups = ref.watch(categoriesProvider).valueOrNull ?? [];

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.rule_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Payee Rules',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Text('Tap a payee to set its default category.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: payees.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Could not load payees')),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text('No payees yet — they appear as you add transactions.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              color: cs.onSurfaceVariant)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, indent: 52,
                          color: cs.outlineVariant.withValues(alpha: 0.35)),
                      itemBuilder: (ctx, i) {
                        final payee = list[i];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              payee.name.isNotEmpty
                                  ? payee.name[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer),
                            ),
                          ),
                          title: Text(payee.name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14, fontWeight: FontWeight.w500,
                                  color: cs.onSurface)),
                          subtitle: payee.defaultCategoryName != null
                              ? Text(payee.defaultCategoryName!,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12, color: cs.primary))
                              : Text('No default category',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _pickCategory(ctx, ref, payee.id, catGroups),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _pickCategory(
    BuildContext context,
    WidgetRef ref,
    String payeeId,
    List catGroups,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<({String id, String name})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryPickerSheet(catGroups: catGroups),
    );
    if (picked == null) return;
    await Supabase.instance.client
        .from('payees')
        .update({'default_category_id': picked.id})
        .eq('id', payeeId);
    ref.invalidate(payeesProvider);
  }
}

// ---------------------------------------------------------------------------
// Security card (PIN / biometric lock)
// ---------------------------------------------------------------------------

class _SecurityCard extends ConsumerWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs   = Theme.of(context).colorScheme;
    final lock = ref.watch(appLockProvider);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // App lock toggle
          SwitchListTile(
            secondary: Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
            title: Text('App lock',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            subtitle: Text(
              lock.isEnabled
                  ? 'Locks after 60 s in background'
                  : 'Require PIN or biometric to open',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
            value: lock.isEnabled,
            activeThumbColor: cs.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onChanged: (on) async {
              if (on) {
                showPinSetupSheet(context, ref);
              } else {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Disable app lock?'),
                    content: const Text('Your PIN will be removed.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(foregroundColor: cs.error),
                          child: const Text('Disable')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(appLockProvider.notifier).disableLock();
                }
              }
            },
          ),

          if (lock.isEnabled) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),

            // Change PIN
            ListTile(
              leading: Icon(Icons.pin_outlined, size: 20, color: cs.onSurfaceVariant),
              title: Text('Change PIN',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              shape: lock.biometricAvailable
                  ? null
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => showPinSetupSheet(context, ref, isChange: true),
            ),

            if (lock.biometricAvailable) ...[
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
              SwitchListTile(
                secondary: Icon(Icons.fingerprint, size: 20, color: cs.onSurfaceVariant),
                title: Text('Face ID / Fingerprint',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text('Use biometrics instead of PIN when available',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                value: lock.biometricEnabled,
                activeThumbColor: cs.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onChanged: (v) =>
                    ref.read(appLockProvider.notifier).setBiometricEnabled(v),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  final List catGroups;
  const _CategoryPickerSheet({required this.catGroups});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text('Pick Category',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final g in catGroups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(g.name.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant, letterSpacing: 0.8)),
                    ),
                    for (final cat in g.categories)
                      ListTile(
                        dense: true,
                        title: Text(cat.name,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, color: cs.onSurface)),
                        onTap: () => Navigator.pop(
                            context, (id: cat.id, name: cat.name)),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
