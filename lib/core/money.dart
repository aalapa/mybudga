/// Sign tests for money held in doubles.
///
/// A category that balances exactly does not land on `0.0`. Budgeted, spent and
/// carried-in amounts are summed as doubles, so an envelope that came out even
/// lands on something like `-1.4e-14` — negative to a computer, zero to anyone
/// reading it, and `$0` once formatted. Compared with `< 0` it announces itself
/// as overspending: "OVERBUDGETED BY $0", a row tinted red with nothing wrong
/// with it, a chip counting offenders that do not exist.
///
/// Half a cent is the threshold because it is the point where the displayed
/// figure stops being `$0.00`. Anything smaller cannot be shown, so it must not
/// be described either.
///
/// These are for wording, colour and counting — not for arithmetic. Sums stay
/// exact; only the decision to *call* a number negative is rounded.
const double kMoneyEpsilon = 0.005;

bool isNegativeMoney(double v) => v < -kMoneyEpsilon;

bool isPositiveMoney(double v) => v > kMoneyEpsilon;

bool isZeroMoney(double v) => v.abs() <= kMoneyEpsilon;
