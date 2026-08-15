import '../../core/theme/semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/account.dart';
import '../../shared/models/emi_plan.dart';
import '../accounts/accounts_provider.dart';
import 'emi_provider.dart';

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/// Opens the "Set up EMI plan" bottom sheet.
/// Optionally pre-fills the CC account field (e.g. when called from an
/// account card).
void showSetupEmiSheet(
  BuildContext context,
  WidgetRef ref, {
  Account? prefillCc,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _SetupEmiSheet(prefillCc: prefillCc, widgetRef: ref),
  );
}

/// Opens the "Pay this installment" confirmation sheet.
void showEmiPaySheet(
  BuildContext context,
  WidgetRef ref,
  EmiPlan plan,
  List<Account> accounts,
) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _EmiPaySheet(plan: plan, accounts: accounts, widgetRef: ref),
  );
}

// ---------------------------------------------------------------------------
// EmiSection — embed this in the Cashflow screen
// ---------------------------------------------------------------------------

class EmiSection extends ConsumerWidget {
  const EmiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans    = ref.watch(emiPlansProvider).valueOrNull ?? [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    if (plans.isEmpty) return const SizedBox.shrink();
    return _EmiSectionBody(plans: plans, accounts: accounts);
  }
}

// ---------------------------------------------------------------------------
// Section body (collapsible list of horizontal cards)
// ---------------------------------------------------------------------------

class _EmiSectionBody extends StatefulWidget {
  final List<EmiPlan> plans;
  final List<Account> accounts;
  const _EmiSectionBody({required this.plans, required this.accounts});

  @override
  State<_EmiSectionBody> createState() => _EmiSectionBodyState();
}

class _EmiSectionBodyState extends State<_EmiSectionBody> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Icon(Icons.credit_score, size: 15, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'EMI PLANS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant, letterSpacing: 0.8,
                    ),
                  ),
                ),
                Text(
                  '${widget.plans.length} active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns:    _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),

        // ── Horizontal card list ────────────────────────────────────────────
        ClipRect(
          child: AnimatedAlign(
            duration:     const Duration(milliseconds: 200),
            curve:        Curves.easeInOut,
            alignment:    Alignment.topLeft,
            heightFactor: _expanded ? 1.0 : 0.0,
            child: SizedBox(
              height: 158,
              child: ListView.separated(
                padding:         const EdgeInsets.fromLTRB(16, 4, 16, 8),
                scrollDirection: Axis.horizontal,
                itemCount:       widget.plans.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _EmiCard(
                  plan:     widget.plans[i],
                  accounts: widget.accounts,
                ),
              ),
            ),
          ),
        ),

        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Individual EMI card
// ---------------------------------------------------------------------------

class _EmiCard extends ConsumerWidget {
  final EmiPlan       plan;
  final List<Account> accounts;
  const _EmiCard({required this.plan, required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final ccAccount = accounts.firstWhere(
      (a) => a.id == plan.ccAccountId,
      orElse: () => Account(
        id: '', householdId: '', name: 'Credit Card',
        type: AccountType.creditCard, isTracking: false, balance: 0,
      ),
    );

    final today     = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    final isOverdue = plan.nextDate.isBefore(todayNorm);
    final borderColor = isOverdue ? cs.error : cs.primaryContainer;

    return GestureDetector(
      onTap: () => _showOptions(context, ref),
      child: Container(
        width: 248,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + progress counter ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${plan.paidMonths}/${plan.totalMonths}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),

            // ── CC account name ───────────────────────────────────────────
            const SizedBox(height: 2),
            Text(
              ccAccount.displayName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10, color: cs.onSurfaceVariant,
              ),
            ),

            // ── Progress bar ──────────────────────────────────────────────
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:           plan.progressFraction,
                minHeight:       5,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(
                  plan.isCompleted ? context.money.positive : cs.primary,
                ),
              ),
            ),

            // ── Next date + amount + pay button ───────────────────────────
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOverdue
                            ? 'OVERDUE'
                            : 'Next · ${DateFormat('MMM d').format(plan.nextDate)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: isOverdue ? cs.error : cs.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        fmt.format(plan.monthlyOutflow),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: cs.onSurface, height: 1.1,
                        ),
                      ),
                      if (plan.monthlyFee > 0)
                        Text(
                          '${fmt.format(plan.monthlyAmount)} + ${fmt.format(plan.monthlyFee)} fee',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9, color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => showEmiPaySheet(context, ref, plan, accounts),
                  style: FilledButton.styleFrom(
                    padding:     const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    minimumSize: const Size(60, 34),
                    backgroundColor: isOverdue ? cs.error : cs.primary,
                  ),
                  child: Text(
                    'Pay',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: isOverdue ? cs.onError : cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Options bottom sheet: pay / close / delete
  void _showOptions(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.description,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${plan.paidMonths}/${plan.totalMonths} paid',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.payment, color: cs.primary),
              title: const Text('Pay this installment'),
              onTap: () {
                Navigator.pop(ctx);
                showEmiPaySheet(context, ref, plan, accounts);
              },
            ),
            ListTile(
              leading: Icon(Icons.block, color: cs.error),
              title: Text('Close plan', style: TextStyle(color: cs.error)),
              subtitle: const Text('Stops future reminders, keeps history'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(emiPlansProvider.notifier).closeEmiPlan(plan.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text('Delete plan', style: TextStyle(color: cs.error)),
              subtitle: const Text('Removes the plan; payment transactions are kept'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, ref);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete EMI plan?'),
        content: Text(
          '"${plan.description}" will be removed. '
          'Existing payment transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(emiPlansProvider.notifier).deleteEmiPlan(plan.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Pay Installment Sheet
// ---------------------------------------------------------------------------

class _EmiPaySheet extends ConsumerStatefulWidget {
  final EmiPlan       plan;
  final List<Account> accounts;
  final WidgetRef     widgetRef;
  const _EmiPaySheet({
    required this.plan,
    required this.accounts,
    required this.widgetRef,
  });

  @override
  ConsumerState<_EmiPaySheet> createState() => _EmiPaySheetState();
}

class _EmiPaySheetState extends ConsumerState<_EmiPaySheet> {
  late String? _fromAccountId;
  DateTime _date  = DateTime.now();
  bool     _saving = false;

  @override
  void initState() {
    super.initState();
    _fromAccountId = widget.plan.fromAccountId;
  }

  List<Account> get _payableAccounts => widget.accounts
      .where((a) => !a.isTracking &&
          (a.type == AccountType.checking ||
           a.type == AccountType.savings  ||
           a.type == AccountType.cash))
      .toList();

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final plan = widget.plan;

    return Container(
      margin:  const EdgeInsets.all(12),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize:      MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              'Pay EMI Installment',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              '${plan.description}  ·  '
              'installment ${plan.paidMonths + 1} of ${plan.totalMonths}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: cs.onSurfaceVariant,
              ),
            ),
          ),

          // Amount summary card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:        cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _SummaryRow('Principal',   fmt.format(plan.monthlyAmount), cs),
                if (plan.monthlyFee > 0) ...[
                  const SizedBox(height: 4),
                  _SummaryRow('Processing fee', fmt.format(plan.monthlyFee), cs),
                  Divider(
                    height: 14,
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ],
                _SummaryRow(
                  'Total payment',
                  fmt.format(plan.monthlyOutflow),
                  cs,
                  highlight: true,
                ),
                if (plan.remainingMonths > 1) ...[
                  const SizedBox(height: 4),
                  _SummaryRow(
                    'Remaining after this',
                    '${plan.remainingMonths - 1} × ${fmt.format(plan.monthlyOutflow)} '
                    '= ${fmt.format((plan.remainingMonths - 1) * plan.monthlyOutflow)}',
                    cs,
                    small: true,
                  ),
                ],
              ],
            ),
          ),

          // From account
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DropdownButtonFormField<String>(
              initialValue: _fromAccountId,
              decoration: InputDecoration(
                labelText: 'Pay from',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12,
                ),
              ),
              hint: const Text('Select account'),
              items: _payableAccounts.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.displayName),
              )).toList(),
              onChanged: (v) => setState(() => _fromAccountId = v),
            ),
          ),

          // Date
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Payment date',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12,
                  ),
                  suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(DateFormat('MMM d, yyyy').format(_date)),
              ),
            ),
          ),

          // Confirm button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _fromAccountId == null || _saving ? null : _confirm,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Confirm  ${fmt.format(plan.monthlyOutflow)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _date,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _confirm() async {
    if (_fromAccountId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(emiPlansProvider.notifier).payInstallment(
        widget.plan,
        fromAccountId: _fromAccountId!,
        date: _date,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Setup EMI Sheet
// ---------------------------------------------------------------------------

class _SetupEmiSheet extends ConsumerStatefulWidget {
  final Account?  prefillCc;
  final WidgetRef widgetRef;
  const _SetupEmiSheet({this.prefillCc, required this.widgetRef});

  @override
  ConsumerState<_SetupEmiSheet> createState() => _SetupEmiSheetState();
}

class _SetupEmiSheetState extends ConsumerState<_SetupEmiSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _descCtrl   = TextEditingController();
  final _totalCtrl  = TextEditingController();
  final _emictrl    = TextEditingController();
  final _feeCtrl    = TextEditingController(text: '0');

  String?   _ccAccountId;
  String?   _fromAccountId;
  int       _months    = 12;
  DateTime  _firstDate = DateTime.now();
  bool      _saving    = false;

  static const _monthOptions = [3, 6, 9, 12, 18, 24];

  @override
  void initState() {
    super.initState();
    _ccAccountId = widget.prefillCc?.id;
    _totalCtrl.addListener(_autoCalcEmi);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _totalCtrl.dispose();
    _emictrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  void _autoCalcEmi() {
    final total = double.tryParse(_totalCtrl.text.replaceAll(',', ''));
    if (total != null && total > 0) {
      final emi = (total / _months);
      _emictrl.text = emi.toStringAsFixed(2);
    }
  }

  List<Account> _ccAccounts(List<Account> all) => all
      .where((a) => !a.isTracking &&
          (a.type == AccountType.creditCard || a.type == AccountType.lineOfCredit))
      .toList();

  List<Account> _payAccounts(List<Account> all) => all
      .where((a) => !a.isTracking &&
          (a.type == AccountType.checking ||
           a.type == AccountType.savings  ||
           a.type == AccountType.cash))
      .toList();

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final ccList   = _ccAccounts(accounts);
    final payList  = _payAccounts(accounts);

    final totalAmount  = double.tryParse(_totalCtrl.text.replaceAll(',', '')) ?? 0;
    final emiAmount    = double.tryParse(_emictrl.text.replaceAll(',', '')) ?? 0;
    final feeAmount    = double.tryParse(_feeCtrl.text.replaceAll(',', '')) ?? 0;
    final totalOutflow = (emiAmount + feeAmount) * _months;
    final totalFees    = feeAmount * _months;
    final fmt          = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Container(
      margin:  const EdgeInsets.all(12),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize:      MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
                child: Text(
                  'Set Up EMI Plan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Track a credit card purchase split into monthly installments.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: cs.onSurfaceVariant,
                  ),
                ),
              ),

              // ── Fields ────────────────────────────────────────────────────

              // Description
              _Pad(child: TextFormField(
                controller:          _descCtrl,
                textCapitalization:  TextCapitalization.sentences,
                decoration: _dec('Description', 'e.g. iPhone 16, Washing machine'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              )),

              // CC account
              _Pad(child: DropdownButtonFormField<String>(
                initialValue: _ccAccountId,
                decoration: _dec('Credit card'),
                items: ccList.map((a) => DropdownMenuItem(
                  value: a.id, child: Text(a.displayName),
                )).toList(),
                onChanged: (v) => setState(() => _ccAccountId = v),
                validator: (v) => v == null ? 'Select a credit card' : null,
              )),

              // Pay-from account (optional)
              _Pad(child: DropdownButtonFormField<String>(
                initialValue: _fromAccountId,
                decoration: _dec('Pay from (optional)'),
                hint:       const Text('Choose at payment time'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Choose at payment time',
                        style: TextStyle(fontStyle: FontStyle.italic)),
                  ),
                  ...payList.map((a) => DropdownMenuItem(
                    value: a.id, child: Text(a.displayName),
                  )),
                ],
                onChanged: (v) => setState(() => _fromAccountId = v),
              )),

              // Total amount
              _Pad(child: TextFormField(
                controller: _totalCtrl,
                decoration: _dec('Total purchase amount', 'e.g. 1000'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  final n = double.tryParse(v?.replaceAll(',', '') ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              )),

              // Months selector
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tenure',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: _monthOptions.map((m) {
                        final sel = m == _months;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _months = m);
                              _autoCalcEmi();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin:  const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sel
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                border: sel
                                    ? Border.all(
                                        color: cs.primary.withValues(alpha: 0.5),
                                      )
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$m',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sel
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    'm',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 9,
                                      color: sel
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // Monthly installment
              _Pad(child: TextFormField(
                controller: _emictrl,
                decoration: _dec(
                  'Monthly installment',
                  'Auto-calculated — adjust if needed',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final n = double.tryParse(v?.replaceAll(',', '') ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              )),

              // Monthly fee
              _Pad(child: TextFormField(
                controller: _feeCtrl,
                decoration: _dec(
                  'Monthly processing fee',
                  '0 if none',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onChanged: (_) => setState(() {}),
              )),

              // First payment date
              _Pad(child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: _dec('First payment date').copyWith(
                    suffixIcon: const Icon(
                      Icons.calendar_today_outlined, size: 18,
                    ),
                  ),
                  child: Text(DateFormat('MMM d, yyyy').format(_firstDate)),
                ),
              )),

              // ── Cost summary ──────────────────────────────────────────────
              if (totalAmount > 0 && emiAmount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        'Monthly payment',
                        fmt.format(emiAmount + feeAmount),
                        cs,
                        highlight: true,
                      ),
                      if (totalFees > 0) ...[
                        const SizedBox(height: 4),
                        _SummaryRow(
                          'Total fees over $_months months',
                          fmt.format(totalFees),
                          cs,
                        ),
                      ],
                      const SizedBox(height: 4),
                      _SummaryRow(
                        'Total cost',
                        fmt.format(totalOutflow),
                        cs,
                      ),
                    ],
                  ),
                ),

              // Create button
              _Pad(child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Create EMI Plan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              )),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
    labelText: label,
    hintText:  hint,
    border:    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _firstDate,
      firstDate:   DateTime.now().subtract(const Duration(days: 31)),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _firstDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final total   = double.parse(_totalCtrl.text.replaceAll(',', ''));
      final monthly = double.parse(_emictrl.text.replaceAll(',', ''));
      final fee     = double.tryParse(_feeCtrl.text.replaceAll(',', '')) ?? 0.0;

      await ref.read(emiPlansProvider.notifier).createEmiPlan(
        description:      _descCtrl.text.trim(),
        ccAccountId:      _ccAccountId!,
        fromAccountId:    _fromAccountId,
        principal:        total,
        monthlyAmount:    monthly,
        monthlyFee:       fee,
        totalMonths:      _months,
        firstPaymentDate: _firstDate,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  final String      label;
  final String      value;
  final ColorScheme cs;
  final bool        highlight;
  final bool        small;
  const _SummaryRow(this.label, this.value, this.cs,
      {this.highlight = false, this.small = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize:   small ? 11 : 13,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          color:      highlight ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
      Text(
        value,
        style: GoogleFonts.plusJakartaSans(
          fontSize:   small ? 11 : 13,
          fontWeight: FontWeight.w700,
          color:      highlight ? cs.primary : cs.onSurface,
        ),
      ),
    ],
  );
}

class _Pad extends StatelessWidget {
  final Widget child;
  const _Pad({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child:   child,
  );
}
