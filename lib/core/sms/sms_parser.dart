import 'dart:convert';

class ParsedSms {
  final double amount;
  final bool isDebit;
  final String? payee;
  final String? accountLastFour;
  final String rawMessage;

  const ParsedSms({
    required this.amount,
    required this.isDebit,
    this.payee,
    this.accountLastFour,
    required this.rawMessage,
  });

  Map<String, dynamic> toJson() => {
    'amount':          amount,
    'isDebit':         isDebit,
    if (payee != null)            'payee':            payee,
    if (accountLastFour != null)  'accountLastFour':  accountLastFour,
    'rawMessage':      rawMessage,
  };

  factory ParsedSms.fromJson(Map<String, dynamic> j) => ParsedSms(
    amount:          (j['amount'] as num).toDouble(),
    isDebit:         j['isDebit'] as bool,
    payee:           j['payee'] as String?,
    accountLastFour: j['accountLastFour'] as String?,
    rawMessage:      j['rawMessage'] as String,
  );

  // Ignore lint — only used to satisfy jsonEncode
  static ParsedSms fromJsonString(String s) =>
      ParsedSms.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

abstract final class SmsParser {
  static const _bankSenders = [
    'HDFCBK', 'ICICIB', 'SBIINB', 'AXISBK', 'KOTAKB', 'YESBNK',
    'PNBSMS', 'BOIIND', 'CANBNK', 'UNIONB', 'INDBNK', 'IDBIBK',
    'SCBLNK', 'CITIBK', 'RBLBNK', 'FEDBK', 'KVBSMS', 'DCBBNK',
    'AUSFIN', 'HSBCIN', 'STANC',  'INDUSB', 'TMBLBK', 'DBSBNK',
    'PAYTMB', 'JUPBNK', 'FIBNK',  'SLICEB', 'NIYOBK',
  ];

  static bool isBankSender(String sender) {
    final up = sender.toUpperCase();
    return _bankSenders.any((s) => up.contains(s));
  }

  // Matches: Rs.1,234.56 | Rs 1234 | INR 1,234 | ₹1234
  static final _amountRe = RegExp(
    r'(?:Rs\.?\s*|INR\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final _debitRe = RegExp(
    r'\b(?:debited?|spent|withdrawn|paid|purchase|deducted)\b',
    caseSensitive: false,
  );

  static final _creditRe = RegExp(
    r'\b(?:credited?|received|deposited|refunded?)\b',
    caseSensitive: false,
  );

  // Matches: A/c XX1234, Acct 1234, Account No. XX1234, ending 1234
  static final _acctRe = RegExp(
    r'(?:ending\s+|a/?c\s*(?:no\.?\s*)?|acct?\.?\s*|account\s*(?:no\.?\s*)?)[xX*]{0,6}(\d{4})',
    caseSensitive: false,
  );

  static final _payeePatterns = [
    // "to SWIGGY" / "at SWIGGY"
    RegExp(
      r'(?:\bat\b|\bto\b)\s+([A-Z][A-Za-z0-9 &\/\-]{1,30}?)(?:\s*[,.]|\s+on\s|\s+[Rr]ef|\s+[Aa]vl|\s+[Aa]vail|\n|$)',
      caseSensitive: false,
    ),
    // "Info: SWIGGY" / "Narration: SWIGGY" / "Trf to SWIGGY"
    RegExp(
      r'(?:Info|Narration|Description|Remarks?|Trf\s*to)[:\s]+([A-Za-z][A-Za-z0-9 &\/\-@.]{1,40}?)(?:[,.]|\s+[Rr]ef|\s+[Aa]vl|\n|$)',
      caseSensitive: false,
    ),
    // UPI/SWIGGY@upi
    RegExp(r'UPI[/\-]([A-Za-z][A-Za-z0-9@._\-]{1,30})', caseSensitive: false),
  ];

  static ParsedSms? parse(String body, {String? sender}) {
    if (sender != null && !isBankSender(sender)) return null;

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;

    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    bool? isDebit;
    if (_debitRe.hasMatch(body))              isDebit = true;
    if (isDebit == null && _creditRe.hasMatch(body)) isDebit = false;
    if (isDebit == null) return null;

    final acctMatch      = _acctRe.firstMatch(body);
    final accountLastFour = acctMatch?.group(1);

    String? payee;
    for (final re in _payeePatterns) {
      final candidate = re.firstMatch(body)?.group(1)?.trim();
      if (candidate != null && candidate.length > 1) {
        payee = candidate;
        break;
      }
    }

    return ParsedSms(
      amount:          amount,
      isDebit:         isDebit,
      payee:           payee,
      accountLastFour: accountLastFour,
      rawMessage:      body,
    );
  }
}
