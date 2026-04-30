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
import '../../shared/providers/categories_provider.dart';
import '../../shared/providers/household_provider.dart';
import '../../shared/providers/payees_provider.dart';
import '../accounts/accounts_provider.dart';
import '../budget/budget_provider.dart';
import '../cashflow/cashflow_provider.dart';
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
  bool _resetting   = false;
  bool _exporting   = false;
  bool _importing   = false;

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

      // 2. Delete split_transactions (has household_id directly)
      await client.from('split_transactions')
          .delete()
          .eq('household_id', householdId);

      // 3-9. Delete in FK-safe order
      await client.from('transactions').delete().eq('household_id', householdId);
      await client.from('scheduled_transactions').delete().eq('household_id', householdId);
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
                leading: _importing
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.tertiary))
                    : Icon(Icons.upload_file_outlined,
                        color: cs.tertiary, size: 20),
                title: Text('Import from YNAB',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.onSurface)),
                subtitle: Text('Import accounts & transactions from YNAB CSV export',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                onTap: _importing ? null : _importFromYnab,
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
                title: Text('Reset budget',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: cs.error)),
                subtitle: Text(
                    'Delete all transactions, categories & budgets',
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
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    final content = String.fromCharCodes(file.bytes ?? []);
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
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    setState(() {
      _budgetPath    = file.name;
      _budgetContent = String.fromCharCodes(file.bytes ?? []);
      _result        = null;
      _error         = null;
    });
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
