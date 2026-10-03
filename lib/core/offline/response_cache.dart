import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// A stored response and when it was fetched.
class CachedResponse {
  final Object? payload;
  final DateTime at;
  const CachedResponse(this.payload, this.at);
}

/// Last-known-good PostgREST responses, kept on disk so the app has something
/// to show without a network.
///
/// Caching happens at the *response* level rather than the model level on
/// purpose: the providers already parse raw JSON into their own types, so
/// storing what Postgres sent needs no per-model serializers and cannot drift
/// out of step with the parsing code.
///
/// Read-only. Nothing here queues or replays a write — the account balances
/// this app shows are maintained by a database trigger, so a write applied
/// locally would not produce the state the server will, and the figures would
/// change under the user after sync. Offline writes therefore still fail, and
/// are reported as needing a connection rather than as an error.
class ResponseCache {
  ResponseCache(this._dir);

  final Directory _dir;

  /// When the data currently on screen was fetched, or null when it is live.
  /// A [ValueNotifier] rather than a provider so that recording a cache hit
  /// during a provider's build does not mutate provider state mid-build.
  final ValueNotifier<DateTime?> servingFrom = ValueNotifier(null);

  static Future<ResponseCache> open() async {
    final base = await getApplicationSupportDirectory();
    final dir  = Directory('${base.path}/response_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return ResponseCache(dir);
  }

  File _file(String key) {
    // Keys carry ids and commas; reduce them to one safe filename.
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${_dir.path}/$safe.json');
  }

  Future<void> put(String key, Object? payload) async {
    try {
      await _file(key).writeAsString(jsonEncode({
        'at': DateTime.now().toIso8601String(),
        'payload': payload,
      }));
    } catch (_) {
      // A cache that cannot be written must never break the live path.
    }
  }

  Future<CachedResponse?> get(String key) async {
    try {
      final f = _file(key);
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return CachedResponse(map['payload'], DateTime.parse(map['at'] as String));
    } catch (_) {
      return null;
    }
  }

  /// Everything cached, dropped. Called on sign-out: one device can hold more
  /// than one household over its life, and rows from the last one must not
  /// survive into the next.
  Future<void> clear() async {
    servingFrom.value = null;
    try {
      if (await _dir.exists()) {
        await for (final f in _dir.list()) {
          if (f is File) await f.delete();
        }
      }
    } catch (_) {}
  }

  /// Fetch, caching the result; on a *network* failure, serve the last good
  /// copy instead.
  ///
  /// Only network failures fall back. A 403, a schema error or a bad query has
  /// to keep surfacing — answering those from cache would hide a real problem
  /// behind data that merely looks right.
  /// Deliberately `dynamic` rather than generic. PostgREST hands back
  /// `List<Map<String, dynamic>>`, but a decoded cache entry is
  /// `List<dynamic>` — so a generic `payload as T` would throw a TypeError on
  /// every cache hit, which is precisely when nothing else can save it.
  /// Callers cast with `as List`, which both shapes satisfy.
  Future<dynamic> read(String key, Future<Object?> Function() fetch) async {
    try {
      final fresh = await fetch();
      await put(key, fresh);
      servingFrom.value = null;
      return fresh;
    } catch (e) {
      if (!isOffline(e)) rethrow;
      final cached = await get(key);
      if (cached == null) rethrow;
      servingFrom.value = cached.at;
      return cached.payload;
    }
  }
}

/// Whether a failure is "no usable network" as opposed to a real error.
///
/// Matched on type and message because the same cause arrives wrapped
/// differently depending on platform, and on whether it came through
/// PostgREST, GoTrue or the raw HTTP client.
bool isOffline(Object e) {
  if (e is SocketException) return true;
  if (e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('no address associated') ||
      s.contains('connection refused') ||
      s.contains('connection closed') ||
      s.contains('connection reset') ||
      s.contains('operation timed out') ||
      s.contains('clientexception');
}

/// What to tell someone whose write just failed.
///
/// Offline is not an error worth showing a stack trace for, and "Could not
/// save: SocketException: Failed host lookup" tells the reader nothing they can
/// act on. [fallback] keeps each call site's own wording for real failures.
String describeWriteFailure(Object e, [String fallback = 'Could not save']) =>
    isOffline(e)
        ? 'You are offline — this needs a connection. Nothing was saved.'
        : '$fallback: $e';

final responseCacheProvider = Provider<ResponseCache>((ref) {
  throw UnimplementedError(
      'responseCacheProvider must be overridden in main.dart');
});
