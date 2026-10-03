import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A row id minted on the client, before the write leaves the device.
///
/// `transactions.id` defaults to `gen_random_uuid()` server-side, and
/// `account.current_balance` is a trigger-maintained accumulator
/// (`current_balance = current_balance + new.amount`). Together those make the
/// ambiguous failure expensive: if the insert reaches Postgres but the response
/// is lost, a second attempt mints a *different* id, so the row lands twice and
/// the balance moves twice.
///
/// Deciding the id here makes a write identifiable before it is sent, which is
/// what any safe retry — manual now, a replay queue later — has to key on.
String newRowId() => _uuid.v4();
