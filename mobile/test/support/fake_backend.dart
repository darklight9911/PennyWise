import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pennywise/core/utils/money.dart';

/// An in-memory imitation of the pennyWise auth API, plugged into Dio as
/// its HTTP adapter. It follows the real server's rules that matter to the
/// app: refresh tokens rotate and a reused one ends the session.
class FakeBackend implements HttpClientAdapter {
  FakeBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  DateTime Function() now;
  Duration accessTtl = const Duration(minutes: 15);

  /// When true, every request fails like a phone with no signal.
  bool offline = false;

  /// Delay for /refresh, to make parallel requests overlap.
  Duration refreshDelay = Duration.zero;

  final users = <String, Map<String, dynamic>>{}; // email -> user
  final passwords = <String, String>{};
  final _access = <String, String>{}; // token -> email
  final _refresh = <String, ({String email, bool used})>{};
  final calls = <String>[]; // "POST /v1/auth/login", ...
  int _n = 0;

  int callCount(String pathSuffix) =>
      calls.where((c) => c.endsWith(pathSuffix)).length;

  /// Receipts: id -> state; file bytes uploaded to the fake bucket.
  final receipts =
      <
        String,
        ({
          String email,
          String transactionId,
          String contentType,
          int size,
          bool uploaded,
        })
      >{};
  final bucket = <String, Uint8List>{};

  /// Code to refuse receipts with (e.g. "receipts_unavailable"), or null.
  String? receiptsError;

  /// True if any upload to the bucket carried the API login token.
  bool uploadSawToken = false;

  /// Daily rates the fake serves: base EUR, quote -> rate (like the ECB).
  final fxRates = <String, String>{};

  /// Creates a user directly (no HTTP), e.g. for login tests.
  void seedUser(String email, String password, {bool verified = false}) {
    users[email] = _user(email, verified: verified);
    passwords[email] = password;
  }

  /// Makes every issued access token invalid, as after a server-side expiry.
  void revokeAllAccessTokens() => _access.clear();

  /// Ends every session (access and refresh tokens), e.g. after a
  /// password change on another phone.
  void revokeAllSessions() {
    _access.clear();
    _refresh.clear();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final path = options.uri.path;
    calls.add('${options.method} $path');
    final body = options.data is Map
        ? (options.data as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final r = await _receiptsRoute(options, path, requestStream);
    if (r != null) {
      return r;
    }

    switch ('${options.method} $path') {
      case 'POST /v1/auth/register':
        final email = (body['email'] as String).toLowerCase();
        if (users.containsKey(email)) {
          return _error(
            409,
            'email_taken',
            'an account with this email already exists',
          );
        }
        if ((body['password'] as String).length < 10) {
          return _error(
            422,
            'validation_failed',
            'password too short',
            field: 'password',
          );
        }
        users[email] = _user(
          email,
          name: body['name'] as String? ?? '',
          currency: body['base_currency'] as String?,
        );
        passwords[email] = body['password'] as String;
        return _json(201, {'user': users[email], 'tokens': _issue(email)});

      case 'POST /v1/auth/login':
        final email = (body['email'] as String).toLowerCase();
        if (passwords[email] != body['password']) {
          return _error(
            401,
            'invalid_credentials',
            'email or password is wrong',
          );
        }
        return _json(200, {'user': users[email], 'tokens': _issue(email)});

      case 'POST /v1/auth/refresh':
        if (refreshDelay > Duration.zero) {
          await Future<void>.delayed(refreshDelay);
        }
        final t = body['refresh_token'] as String;
        final rt = _refresh[t];
        if (rt == null) {
          return _error(401, 'invalid_refresh_token', 'session expired');
        }
        if (rt.used) {
          // Reuse = theft: kill every refresh token of this user.
          _refresh.removeWhere((_, v) => v.email == rt.email);
          return _error(401, 'invalid_refresh_token', 'session expired');
        }
        _refresh[t] = (email: rt.email, used: true);
        return _json(200, {'tokens': _issue(rt.email)});

      case 'POST /v1/auth/logout':
        _refresh.remove(body['refresh_token']);
        return _empty(204);

      case 'POST /v1/auth/verify-email':
        if (body['token'] != 'good-token') {
          return _error(
            400,
            'invalid_link',
            'this link is invalid or has expired',
          );
        }
        for (final u in users.values) {
          u['email_verified'] = true;
        }
        return _empty(204);

      case 'POST /v1/auth/forgot-password':
        return _empty(202);

      case 'POST /v1/auth/reset-password':
        return body['token'] == 'good-token'
            ? _empty(204)
            : _error(
                400,
                'invalid_link',
                'this link is invalid or has expired',
              );

      case 'POST /v1/auth/resend-verification':
      case 'GET /v1/me':
        final auth = options.headers['Authorization'] as String?;
        final email = auth == null
            ? null
            : _access[auth.replaceFirst('Bearer ', '')];
        if (email == null) {
          return _error(
            401,
            'invalid_token',
            'access token is invalid or expired',
          );
        }
        return path.endsWith('/me')
            ? _json(200, {'user': users[email]})
            : _empty(202);

      case 'PATCH /v1/me':
        final email = _emailOf(options);
        if (email == null) {
          return _error(401, 'invalid_token', 'invalid');
        }
        final u = users[email]!;
        final next = body['base_currency'] as String?;
        if (next != null && next != u['base_currency']) {
          if (u['base_currency_status'] != 'ok') {
            return _error(409, 'recalculating', 'still being applied');
          }
          u['base_currency'] = next;
          u['base_currency_status'] = 'recalculating';
        }
        return _json(200, {'user': u});

      case 'GET /v1/fx/rates':
        final base = options.uri.queryParameters['base'] ?? 'EUR';
        final eur = {'EUR': '1', ...fxRates};
        if (!eur.containsKey(base) || fxRates.isEmpty) {
          return _error(404, 'no_rates', 'no daily rate');
        }
        return _json(200, {
          'base': base,
          'date': '2026-11-17',
          'rates': {
            for (final e in eur.entries)
              if (e.key != base)
                e.key: (double.parse(e.value) / double.parse(eur[base]!))
                    .toStringAsFixed(10),
          },
        });

      case 'DELETE /v1/me':
        final auth = options.headers['Authorization'] as String?;
        final email = auth == null
            ? null
            : _access[auth.replaceFirst('Bearer ', '')];
        if (email == null) {
          return _error(401, 'invalid_token', 'access token is invalid');
        }
        if (passwords[email] != body['password']) {
          return _error(403, 'wrong_password', 'the password is wrong');
        }
        users.remove(email);
        passwords.remove(email);
        _access.removeWhere((_, e) => e == email);
        _refresh.removeWhere((_, v) => v.email == email);
        return _empty(204);

      case 'POST /v1/sync/push':
      case 'GET /v1/sync/pull':
        final auth = options.headers['Authorization'] as String?;
        final email = auth == null
            ? null
            : _access[auth.replaceFirst('Bearer ', '')];
        if (email == null) {
          return _error(401, 'invalid_token', 'access token is invalid');
        }
        if (options.method == 'GET') {
          final since = int.parse('${options.queryParameters['since'] ?? 0}');
          return _json(200, _pull(email, since));
        }
        final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
        final results = _push(email, changes);
        await onPush?.call();
        return _json(200, {'results': results, 'version': syncVersion[email]});
    }
    return _error(404, 'not_found', 'route not found');
  }

  // ------------------------------------------------------------- fake sync

  /// Rows on the "server": (entity, id) -> row.
  final serverRows = <(String, String), FakeServerRow>{};
  final syncVersion = <String, int>{};

  /// Page size of pull (small values test paging).
  int pullPageSize = 1000;

  /// Runs after a push was applied but before its reply arrives, e.g. to
  /// simulate the user editing the same row meanwhile.
  Future<void> Function()? onPush;

  /// Puts a row on the server as if another device had pushed it.
  void serverWrite(
    String email,
    String entity,
    String id,
    Map<String, dynamic> data, {
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) {
    final v = syncVersion[email] = (syncVersion[email] ?? 0) + 1;
    serverRows[(entity, id)] = FakeServerRow(
      owner: email,
      entity: entity,
      id: id,
      data: data,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: v,
    );
  }

  List<Map<String, dynamic>> _push(
    String email,
    List<Map<String, dynamic>> changes,
  ) {
    final v = syncVersion[email] = (syncVersion[email] ?? 0) + 1;
    return [
      for (final c in changes)
        () {
          final key = (c['entity'] as String, c['id'] as String);
          final result = {'entity': key.$1, 'id': key.$2};
          final data = (c['data'] as Map).cast<String, dynamic>();
          if (data['name'] == 'REJECT ME' || data['note'] == 'REJECT ME') {
            return {
              ...result,
              'status': 'rejected',
              'error': {'code': 'invalid', 'message': 'rejected by test'},
            };
          }
          final updatedAt = DateTime.parse(c['updated_at'] as String);
          final existing = serverRows[key];
          if (existing != null && !existing.updatedAt.isBefore(updatedAt)) {
            return {...result, 'status': 'stale'};
          }
          if (key.$1 == 'transaction') _addBaseAmount(email, data);
          serverRows[key] = FakeServerRow(
            owner: email,
            entity: key.$1,
            id: key.$2,
            data: data,
            updatedAt: updatedAt,
            deletedAt: c['deleted_at'] == null
                ? null
                : DateTime.parse(c['deleted_at'] as String),
            version: v,
          );
          return {...result, 'status': 'applied'};
        }(),
    ];
  }

  Future<ResponseBody?> _receiptsRoute(
    RequestOptions options,
    String path,
    Stream<Uint8List>? body,
  ) async {
    // The storage bucket (R2), reached with the signed URL only.
    if (options.uri.host == 'r2.example.com') {
      if (options.headers.containsKey('Authorization')) {
        uploadSawToken = true;
      }
      final id = path.split('/').last;
      final bytes = <int>[];
      if (body != null) {
        await for (final chunk in body) {
          bytes.addAll(chunk);
        }
      }
      final want = receipts[id];
      if (options.method != 'PUT' ||
          want == null ||
          bytes.length != want.size) {
        return _error(403, 'signature', 'does not match the signature');
      }
      bucket[id] = Uint8List.fromList(bytes);
      return _empty(200);
    }
    if (!path.startsWith('/v1/receipts')) {
      return null;
    }
    final email = _emailOf(options);
    if (email == null) {
      return _error(401, 'invalid_token', 'invalid');
    }
    if (receiptsError != null) {
      return _error(503, receiptsError!, 'refused by test');
    }
    final data = options.data is Map
        ? (options.data as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    if (options.method == 'POST' && path == '/v1/receipts/upload-url') {
      final id = data['id'] as String;
      final tx = serverRows[('transaction', data['transaction_id'] as String)];
      if (tx == null || tx.deletedAt != null || tx.owner != email) {
        return _error(
          409,
          'transaction_not_synced',
          'sync the transaction first',
        );
      }
      receipts[id] = (
        email: email,
        transactionId: data['transaction_id'] as String,
        contentType: data['content_type'] as String,
        size: data['size_bytes'] as int,
        uploaded: false,
      );
      return _json(200, {
        'id': id,
        'url': 'https://r2.example.com/put/$id',
        'method': 'PUT',
        'headers': {
          'Content-Type': data['content_type'],
          'Content-Length': '${data['size_bytes']}',
        },
      });
    }
    final parts = path.split('/'); // ['', 'v1', 'receipts', id, ...]
    final id = parts.length > 3 ? parts[3] : '';
    final rec = receipts[id];
    if (rec == null || rec.email != email) {
      return _error(404, 'not_found', 'receipt not found');
    }
    if (options.method == 'POST' && path.endsWith('/confirm')) {
      if (!bucket.containsKey(id)) {
        return _error(409, 'not_uploaded', 'not there yet');
      }
      receipts[id] = (
        email: rec.email,
        transactionId: rec.transactionId,
        contentType: rec.contentType,
        size: rec.size,
        uploaded: true,
      );
      serverWrite(email, 'receipt', id, {
        'transaction_id': rec.transactionId,
        'content_type': rec.contentType,
        'size_bytes': rec.size,
      }, updatedAt: DateTime.now().toUtc());
      return _empty(204);
    }
    if (options.method == 'GET' && path.endsWith('/url')) {
      return _json(200, {
        'url': 'https://r2.example.com/get/$id',
        'expires_at': '2099-01-01T00:00:00Z',
      });
    }
    if (options.method == 'DELETE') {
      final row = serverRows[('receipt', id)];
      receipts.remove(id);
      bucket.remove(id);
      if (row != null) {
        serverWrite(
          email,
          'receipt',
          id,
          row.data,
          updatedAt: DateTime.now().toUtc(),
          deletedAt: DateTime.now().toUtc(),
        );
      }
      return _empty(204);
    }
    return _error(404, 'not_found', 'route not found');
  }

  String? _emailOf(RequestOptions options) {
    final auth = options.headers['Authorization'] as String?;
    return auth == null ? null : _access[auth.replaceFirst('Bearer ', '')];
  }

  /// Like the real server: the main-currency amount at rate 1, at the
  /// typed rate, or empty (no daily rates in this fake).
  void _addBaseAmount(String email, Map<String, dynamic> data) {
    final base = users[email]?['base_currency'] as String? ?? 'USD';
    final currency = data['currency'] as String;
    final amount = data['amount_minor'] as int;
    final typed = data.remove('manual_fx_rate') as String?;
    if (currency == base) {
      data.addAll({
        'fx_rate_to_base': '1',
        'fx_rate_source': 'auto',
        'amount_base_minor': amount,
      });
    } else if (typed != null) {
      data.addAll({
        'fx_rate_to_base': typed,
        'fx_rate_source': 'manual',
        'amount_base_minor': convertMinor(amount, currency, base, typed),
      });
    } else {
      data.addAll({
        'fx_rate_to_base': null,
        'fx_rate_source': null,
        'amount_base_minor': null,
      });
    }
  }

  Map<String, dynamic> _pull(String email, int since) {
    const order = {
      'account': 0,
      'category': 1,
      'recurring_rule': 2,
      'due': 3,
      'transaction': 4,
      'budget': 5,
      'goal': 6,
      'goal_contribution': 7,
      'receipt': 8,
    };
    final rows =
        serverRows.values
            .where((r) => r.owner == email && r.version > since)
            .toList()
          ..sort((a, b) {
            final v = a.version.compareTo(b.version);
            return v != 0
                ? v
                : (order[a.entity] ?? 9).compareTo(order[b.entity] ?? 9);
          });
    var page = rows;
    var hasMore = false;
    if (rows.length > pullPageSize) {
      hasMore = true;
      page = rows.take(pullPageSize).toList();
      // Never split one push across pages (like the real server).
      final last = rows[pullPageSize].version;
      page = page.where((r) => r.version != last).toList();
    }
    return {
      'changes': [for (final r in page) r.toPullJson()],
      'cursor': page.isEmpty ? (syncVersion[email] ?? 0) : page.last.version,
      'has_more': hasMore,
    };
  }

  Map<String, dynamic> _issue(String email) {
    _n++;
    final access = 'access-$_n';
    final refresh = 'refresh-$_n';
    _access[access] = email;
    _refresh[refresh] = (email: email, used: false);
    return {
      'access_token': access,
      'access_expires_at': now().add(accessTtl).toUtc().toIso8601String(),
      'refresh_token': refresh,
      'refresh_expires_at': now()
          .add(const Duration(days: 30))
          .toUtc()
          .toIso8601String(),
      'token_type': 'Bearer',
    };
  }

  Map<String, dynamic> _user(
    String email, {
    String name = '',
    String? currency,
    bool verified = false,
  }) => {
    'id': 'user-${email.hashCode}',
    'email': email,
    'name': name,
    'base_currency': currency ?? 'USD',
    'base_currency_status': 'ok',
    'locale': 'en',
    'timezone': 'UTC',
    'email_verified': verified,
    'has_password': true,
    'google_linked': false,
    'created_at': '2026-11-15T00:00:00Z',
  };

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  ResponseBody _error(
    int status,
    String code,
    String message, {
    String? field,
  }) => _json(status, {
    'error': {'code': code, 'message': message, 'field': ?field},
  });

  ResponseBody _empty(int status) => ResponseBody.fromString('', status);

  @override
  void close({bool force = false}) {}
}

class FakeServerRow {
  FakeServerRow({
    required this.owner,
    required this.entity,
    required this.id,
    required this.data,
    required this.updatedAt,
    required this.version,
    this.deletedAt,
  });

  final String owner, entity, id;
  final Map<String, dynamic> data;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Map<String, dynamic> toPullJson() => {
    'entity': entity,
    'id': id,
    'version': version,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'data': data,
  };
}
