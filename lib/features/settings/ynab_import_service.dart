// ignore_for_file: avoid_print
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/account.dart';

// =============================================================================
// Public result types
// =============================================================================

class YnabImportPreview {
  final int accounts;
  final int categories;
  final int transactions;

  const YnabImportPreview({
    required this.accounts,
    required this.categories,
    required this.transactions,
  });
}

class YnabImportResult {
  final int accounts;
  final int categories;
  final int payees;
  final int transactions;
  final int budgetEntries;
  final List<String> warnings;

  const YnabImportResult({
    required this.accounts,
    required this.categories,
    required this.payees,
    required this.transactions,
    required this.budgetEntries,
    this.warnings = const [],
  });
}

// =============================================================================
// Internal parsed row models
// =============================================================================

class _RegRow {
  final String account;
  final DateTime date;
  final String payee;
  final String masterCategory;
  final String subCategory;
  final String memo;
  final double outflow;
  final double inflow;
  final bool cleared;

  const _RegRow({
    required this.account,
    required this.date,
    required this.payee,
    required this.masterCategory,
    required this.subCategory,
    required this.memo,
    required this.outflow,
    required this.inflow,
    required this.cleared,
  });

  double get amount => inflow - outflow;
  bool get isStartingBalance => payee.trim() == 'Starting Balance';
  bool get isTransfer => payee.trim().startsWith('Transfer :');
}

class _BudgetRow {
  final DateTime month;
  final String masterCategory;
  final String subCategory;
  final double budgeted;

  const _BudgetRow({
    required this.month,
    required this.masterCategory,
    required this.subCategory,
    required this.budgeted,
  });
}

// =============================================================================
// Service
// =============================================================================

class YnabImportService {
  final SupabaseClient _client;
  final String _householdId;

  YnabImportService({
    required SupabaseClient client,
    required String householdId,
  })  : _client = client,
        _householdId = householdId;

  // ---------------------------------------------------------------------------
  // Preview (no DB writes)
  // ---------------------------------------------------------------------------

  static YnabImportPreview preview({
    required String registerCsv,
    DateTime? fromDate,
  }) {
    final rows = _parseRegister(registerCsv);

    final accounts = rows.map((r) => r.account).toSet();

    final categories = <String>{};
    for (final r in rows) {
      if (r.masterCategory.isNotEmpty &&
          r.subCategory.isNotEmpty &&
          r.masterCategory != 'Hidden Categories' &&
          r.masterCategory != 'Uncategorized Transactions') {
        categories.add('${r.masterCategory}|${r.subCategory}');
      }
    }

    final filtered = fromDate != null
        ? rows.where((r) => !r.date.isBefore(fromDate)).toList()
        : rows;

    final txCount =
        filtered.where((r) => !r.isStartingBalance).length;

    return YnabImportPreview(
      accounts:     accounts.length,
      categories:   categories.length,
      transactions: txCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Full import
  // ---------------------------------------------------------------------------

  Future<YnabImportResult> import({
    required String registerCsv,
    String? budgetCsv,
    DateTime? fromDate,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final warnings = <String>[];

    onProgress?.call('Parsing CSV…', 0.02);
    final rows = _parseRegister(registerCsv);
    final budgetRows =
        budgetCsv != null ? _parseBudget(budgetCsv) : <_BudgetRow>[];

    // 1. Categories
    onProgress?.call('Creating categories…', 0.10);
    final catIdMap = await _importCategories(rows, budgetRows, warnings);

    // 2. Payees
    onProgress?.call('Creating payees…', 0.28);
    final payeeIdMap = await _importPayees(rows, catIdMap);

    // 3. Accounts
    onProgress?.call('Creating accounts…', 0.42);
    final accountIdMap = await _importAccounts(rows, warnings);

    // 4. Transactions
    onProgress?.call('Importing transactions…', 0.55);
    final txCount = await _importTransactions(
      rows, accountIdMap, catIdMap, payeeIdMap, fromDate, warnings,
      onProgress: (p) => onProgress?.call(
          'Importing transactions… ${(p * 100).round()}%', 0.55 + p * 0.35),
    );

    // 5. Budget allocations (most recent month only)
    int budgetCount = 0;
    if (budgetRows.isNotEmpty) {
      onProgress?.call('Importing budget…', 0.92);
      budgetCount =
          await _importBudgetCurrentMonth(budgetRows, catIdMap, warnings);
    }

    onProgress?.call('Done!', 1.0);

    return YnabImportResult(
      accounts:     accountIdMap.length,
      categories:   catIdMap.length,
      payees:       payeeIdMap.length,
      transactions: txCount,
      budgetEntries: budgetCount,
      warnings:     warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 – categories
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _importCategories(
    List<_RegRow> rows,
    List<_BudgetRow> budgetRows,
    List<String> warnings,
  ) async {
    // Collect unique (group, category) pairs — skip hidden / CC payment
    final pairs = <String, String>{}; // 'group|cat' → group name

    void addPair(String group, String cat) {
      if (group.isEmpty || cat.isEmpty) return;
      if (group == 'Hidden Categories') return;
      if (group == 'Uncategorized Transactions') return;
      if (group == 'Credit Card Payments') return;
      if (cat.toLowerCase().contains('payment') &&
          group.toLowerCase().contains('credit card')) { return; }
      pairs['$group|$cat'] = group;
    }

    for (final r in rows) {
      if (r.masterCategory.isNotEmpty && r.subCategory.isNotEmpty) {
        addPair(r.masterCategory, r.subCategory);
      }
    }
    for (final b in budgetRows) {
      addPair(b.masterCategory, b.subCategory);
    }

    if (pairs.isEmpty) return {};

    // Create groups
    final groups = pairs.values.toSet();
    final groupInserts = groups.map((g) => {
          'household_id': _householdId,
          'name':         g,
          'sort_order':   0,
        }).toList();

    final groupRows = await _client
        .from('category_groups')
        .insert(groupInserts)
        .select('id, name');

    final groupIdMap = <String, String>{};
    for (final r in groupRows as List) {
      groupIdMap[r['name'] as String] = r['id'] as String;
    }

    // Create categories
    final catInserts = <Map<String, dynamic>>[];
    for (final entry in pairs.entries) {
      final parts = entry.key.split('|');
      final groupName = parts[0];
      final catName  = parts.length > 1 ? parts[1] : parts[0];
      final groupId  = groupIdMap[groupName];
      if (groupId == null) continue;
      catInserts.add({
        'household_id':      _householdId,
        'category_group_id': groupId,
        'name':              catName,
        'sort_order':        0,
      });
    }

    final catRows = await _client
        .from('categories')
        .insert(catInserts)
        .select('id, name');

    final catIdMap = <String, String>{};
    for (final r in catRows as List) {
      catIdMap[r['name'] as String] = r['id'] as String;
    }

    return catIdMap;
  }

  // ---------------------------------------------------------------------------
  // Step 2 – payees
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _importPayees(
    List<_RegRow> rows,
    Map<String, String> catIdMap,
  ) async {
    final payeeMap = <String, String?>{}; // payee name → last used cat id

    for (final r in rows) {
      if (r.isStartingBalance || r.payee.trim().isEmpty) continue;
      final catId = r.subCategory.isNotEmpty ? catIdMap[r.subCategory] : null;
      payeeMap.putIfAbsent(r.payee.trim(), () => catId);
      if (catId != null) payeeMap[r.payee.trim()] = catId;
    }

    if (payeeMap.isEmpty) return {};

    final inserts = payeeMap.entries.map((e) => {
          'household_id':        _householdId,
          'name':                e.key,
          'default_category_id': e.value,
        }).toList();

    // Batch insert payees
    final payeeIdMap = <String, String>{};
    for (final chunk in _chunks(inserts, 250)) {
      final result = await _client
          .from('payees')
          .insert(chunk)
          .select('id, name');
      for (final r in result as List) {
        payeeIdMap[r['name'] as String] = r['id'] as String;
      }
    }

    return payeeIdMap;
  }

  // ---------------------------------------------------------------------------
  // Step 3 – accounts
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _importAccounts(
    List<_RegRow> rows,
    List<String> warnings,
  ) async {
    // Collect starting balances per account
    final startingBalances = <String, double>{};
    final startDates       = <String, DateTime>{};

    for (final r in rows) {
      if (r.isStartingBalance) {
        startingBalances[r.account] = r.amount;
        startDates[r.account] = r.date;
      }
    }

    final accounts = rows.map((r) => r.account).toSet();
    final inserts  = <Map<String, dynamic>>[];

    for (final name in accounts) {
      final (type, isTracking) = _inferAccountType(name);
      final startBal = startingBalances[name] ?? 0.0;
      final lastFour = _extractLastFour(name, type);

      inserts.add({
        'household_id':    _householdId,
        'name':            name,
        'account_type':    type.toDb,
        'is_tracking':     isTracking || type.defaultTracking,
        'starting_balance': startBal,
        'current_balance':  startBal,
        'last_four': lastFour,
        'start_date': startDates[name] != null ? _toDateStr(startDates[name]!) : null,
      });
    }

    final result = await _client
        .from('accounts')
        .insert(inserts)
        .select('id, name');

    final accountIdMap = <String, String>{};
    for (final r in result as List) {
      accountIdMap[r['name'] as String] = r['id'] as String;
    }
    return accountIdMap;
  }

  // ---------------------------------------------------------------------------
  // Step 4 – transactions
  // ---------------------------------------------------------------------------

  Future<int> _importTransactions(
    List<_RegRow> rows,
    Map<String, String> accountIdMap,
    Map<String, String> catIdMap,
    Map<String, String> payeeIdMap,
    DateTime? fromDate,
    List<String> warnings, {
    void Function(double)? onProgress,
  }) async {
    final filtered = rows
        .where((r) => !r.isStartingBalance)
        .where((r) => fromDate == null || !r.date.isBefore(fromDate))
        .toList();

    final inserts = <Map<String, dynamic>>[];

    for (final r in filtered) {
      final accountId = accountIdMap[r.account];
      if (accountId == null) {
        warnings.add('Unknown account: ${r.account}');
        continue;
      }

      final catId   = r.subCategory.isNotEmpty ? catIdMap[r.subCategory] : null;
      final payeeId = r.payee.trim().isNotEmpty ? payeeIdMap[r.payee.trim()] : null;

      inserts.add({
        'household_id': _householdId,
        'account_id':   accountId,
        'payee_id':     payeeId,
        'category_id':  catId,
        'amount':       r.amount,
        'date':         _toDateStr(r.date),
        'memo':         r.memo.isNotEmpty ? r.memo : null,
        'cleared':      r.cleared,
        'status':       'confirmed',
      });
    }

    // Batch insert in chunks
    int count = 0;
    final chunks = _chunks(inserts, 200);
    for (int i = 0; i < chunks.length; i++) {
      await _client.from('transactions').insert(chunks[i]);
      count += chunks[i].length;
      onProgress?.call((i + 1) / chunks.length);
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Step 5 – budget allocations (most recent month only)
  // ---------------------------------------------------------------------------

  Future<int> _importBudgetCurrentMonth(
    List<_BudgetRow> rows,
    Map<String, String> catIdMap,
    List<String> warnings,
  ) async {
    // Find most recent month in budget rows
    DateTime? latestMonth;
    for (final r in rows) {
      if (latestMonth == null || r.month.isAfter(latestMonth)) {
        latestMonth = r.month;
      }
    }
    if (latestMonth == null) return 0;

    final month     = DateTime(latestMonth.year, latestMonth.month, 1);
    final monthStr  = _toDateStr(month);

    final inserts = <Map<String, dynamic>>[];

    for (final r in rows) {
      if (r.month.year != month.year || r.month.month != month.month) continue;
      if (r.budgeted == 0) continue;
      if (r.masterCategory == 'Hidden Categories') continue;
      if (r.masterCategory == 'Uncategorized Transactions') continue;
      if (r.masterCategory == 'Credit Card Payments') continue;

      final catId = catIdMap[r.subCategory];
      if (catId == null) continue;

      inserts.add({
        'household_id': _householdId,
        'category_id':  catId,
        'month':        monthStr,
        'budgeted':     r.budgeted,
      });
    }

    if (inserts.isEmpty) return 0;

    // Upsert in case any already exist (from CC trigger side effects)
    await _client
        .from('budget_months')
        .upsert(inserts, onConflict: 'household_id,category_id,month');

    return inserts.length;
  }

  // ---------------------------------------------------------------------------
  // CSV parsers
  // ---------------------------------------------------------------------------

  static List<_RegRow> _parseRegister(String csv) {
    final rows    = _parseCsv(csv);
    if (rows.isEmpty) return [];

    // Find column indices from header
    final header = rows.first.map((s) => s.toLowerCase().trim()).toList();
    int col(String name) => header.indexOf(name);

    final iAccount  = col('account');
    final iDate     = col('date');
    final iPayee    = col('payee');
    final iMaster   = col('master category');
    final iSub      = col('sub category');
    final iMemo     = col('memo');
    final iOutflow  = col('outflow');
    final iInflow   = col('inflow');
    final iCleared  = col('cleared');

    final result = <_RegRow>[];

    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.length <= iCleared) continue;

      final date = _parseDate(_field(r, iDate));
      if (date == null) continue;

      result.add(_RegRow(
        account:        _field(r, iAccount),
        date:           date,
        payee:          _field(r, iPayee),
        masterCategory: _field(r, iMaster),
        subCategory:    _field(r, iSub),
        memo:           _field(r, iMemo),
        outflow:        _parseAmount(_field(r, iOutflow)),
        inflow:         _parseAmount(_field(r, iInflow)),
        cleared:        ['R', 'C'].contains(_field(r, iCleared).toUpperCase()),
      ));
    }
    return result;
  }

  static List<_BudgetRow> _parseBudget(String csv) {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) return [];

    final header = rows.first.map((s) => s.toLowerCase().trim()).toList();
    int col(String name) => header.indexOf(name);

    final iMonth    = col('month');
    final iMaster   = col('master category');
    final iSub      = col('sub category');
    final iBudgeted = col('budgeted');

    final result = <_BudgetRow>[];

    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.length <= iBudgeted) continue;

      final month = _parseMonthName(_field(r, iMonth));
      if (month == null) continue;

      final master = _field(r, iMaster).trim();
      final sub    = _field(r, iSub).trim();
      if (master.isEmpty || sub.isEmpty) continue;
      if (master == 'Hidden Categories') continue;

      final budgeted = _parseAmount(_field(r, iBudgeted));

      result.add(_BudgetRow(
        month:          month,
        masterCategory: master,
        subCategory:    sub,
        budgeted:       budgeted,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // CSV field helpers
  // ---------------------------------------------------------------------------

  static String _field(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index].trim() : '';

  static List<List<String>> _parseCsv(String content) {
    // Normalize line endings
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final result = <List<String>>[];

    for (final line in content.split('\n')) {
      if (line.trim().isEmpty) continue;
      result.add(_parseLine(line));
    }
    return result;
  }

  static List<String> _parseLine(String line) {
    final fields = <String>[];
    final sb     = StringBuffer();
    bool inQ     = false;

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQ && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = !inQ;
        }
      } else if (c == ',' && !inQ) {
        fields.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    fields.add(sb.toString());
    return fields;
  }

  // ---------------------------------------------------------------------------
  // Value parsers
  // ---------------------------------------------------------------------------

  /// Parse YNAB dollar string: "$1,234.56", "-$1,234.56", "$0.00"
  static double _parseAmount(String s) {
    s = s.trim();
    if (s.isEmpty) return 0.0;
    final negative = s.startsWith('-');
    s = s.replaceAll(RegExp(r'[\$,\s\-]'), '');
    final value = double.tryParse(s) ?? 0.0;
    return negative ? -value : value;
  }

  /// Parse YNAB date: "MM/DD/YYYY"
  static DateTime? _parseDate(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final parts = s.split('/');
    if (parts.length != 3) return null;
    try {
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse YNAB budget month: "April 2026"
  static DateTime? _parseMonthName(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final parts = s.split(' ');
    if (parts.length < 2) return null;
    final monthNames = [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ];
    final monthNum = monthNames.indexOf(parts[0].toLowerCase()) + 1;
    if (monthNum == 0) return null;
    final year = int.tryParse(parts[1]);
    if (year == null) return null;
    return DateTime(year, monthNum, 1);
  }

  static String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Account type inference
  // ---------------------------------------------------------------------------

  static (AccountType, bool) _inferAccountType(String name) {
    final l = name.toLowerCase();

    // Loans & debts (check before generic keywords)
    if (l.contains('mortgage')) return (AccountType.mortgage, true);
    if (l.contains('personal loan') || l.contains('amex loan') ||
        l.contains('devi amex') || l.contains('emi')) {
      return (AccountType.loan, true);
    }
    if (l.contains('mfs') || l.contains('carmax') || l.contains('toyota') ||
        l.contains('honda') || l.contains('highlander') ||
        l.contains('loan')) {
      return (AccountType.loan, true);
    }

    // Investments (check before checking/savings)
    if (l.contains('investment') || l.contains('roth') || l.contains('ira') ||
        l.contains('401k') || l.contains('fidelity') ||
        l.contains('vanguard')) {
      return (AccountType.investment, true);
    }

    // Assets (escrow, property)
    if (l.contains('escrow') || l.contains('asset') ||
        l.contains('property')) {
      return (AccountType.asset, true);
    }

    // Checking / Savings
    if (l.contains('checking')) return (AccountType.checking, false);
    if (l.contains('savings')) return (AccountType.savings, false);
    if (l.contains('cash')) return (AccountType.cash, false);

    // Credit cards (common banks / card names)
    if (l.contains('amex') || l.contains('apple card') ||
        l.contains('discover') || l.contains('freedom') ||
        l.contains('unlimited') || l.contains('capital one') ||
        l.contains('savor') || l.contains('qsilver') ||
        l.contains('amazon') || l.contains('credit card') ||
        l.contains('hilton') || l.contains('visa') ||
        l.contains('mastercard')) {
      return (AccountType.creditCard, false);
    }

    return (AccountType.checking, false);
  }

  /// Extract last-4 digits suffix from account name (e.g. "Chase - 1234" → "1234")
  static String? _extractLastFour(String name, AccountType type) {
    if (type != AccountType.creditCard) return null;
    final match = RegExp(r'[-\s](\d{1,4})$').firstMatch(name);
    final digits = match?.group(1);
    if (digits == null || digits.length > 4) return null;
    return digits.padLeft(4, '0');
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static List<List<T>> _chunks<T>(List<T> list, int size) {
    final result = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      result.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return result;
  }
}
