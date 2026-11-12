import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class OnlineSession {
  OnlineSession(this.api, {FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );
  final ScanApi api;
  final FlutterSecureStorage _storage;
  static const storageKey = 'scanpdf.online.session.v1';
  String? userId;
  String? email;
  String? _access, _refresh;
  int _expiry = 0, _epoch = 0;
  bool _remember = false;
  Future<String>? _renewing;
  String? get owner => userId == null ? null : 'auth:$userId';

  Future<void> restore() async {
    final stored = await _storage.read(key: storageKey);
    if (stored == null) return;
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      if (data['base'] != api.base.toString()) {
        await clear();
        return;
      }
      userId = data['id'] as String;
      email = data['email'] as String;
      _refresh = data['refresh'] as String;
      _remember = true;
    } on FormatException {
      await clear();
    } on TypeError {
      await clear();
    }
  }

  Future<void> register(String email, String password) async {
    await api.json(
      'POST',
      'auth/register',
      body: {'email': email, 'password': password},
    );
  }

  Future<void> login(
    String email,
    String password, {
    required bool remember,
  }) async {
    await clear();
    final epoch = _epoch;
    final data = await api.json(
      'POST',
      'auth/login',
      body: {'email': email, 'password': password},
    );
    _remember = remember;
    await _accept(data, epoch);
  }

  Future<String> _accept(Map<String, dynamic> data, int epoch) async {
    if (epoch != _epoch) throw const ApiFailure(401, 'Phiên đã kết thúc.');
    final user = data['user'] as Map<String, dynamic>;
    final id = user['id'] as String;
    if (userId != null && userId != id) {
      throw const ApiFailure(401, 'Tài khoản của phiên không khớp.');
    }
    userId = id;
    email = user['email'] as String;
    _access = data['access_token'] as String;
    _refresh = data['refresh_token'] as String;
    _expiry = data['expires_at'] as int;
    final accepted = _access!;
    if (_remember) {
      await _storage.write(
        key: storageKey,
        value: jsonEncode({
          'base': api.base.toString(),
          'id': userId,
          'email': email,
          'refresh': _refresh,
        }),
      );
    }
    if (epoch != _epoch) throw const ApiFailure(401, 'Phiên đã kết thúc.');
    return accepted;
  }

  Future<String> _token({String? rejected}) {
    if (_renewing case final pending?) return pending;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_access != null && _access != rejected && _expiry > now + 15) {
      return Future.value(_access);
    }
    final refresh = _refresh;
    if (refresh == null) {
      return Future.error(const ApiFailure(401, 'Hãy đăng nhập lại.'));
    }
    final epoch = _epoch;
    return _renewing = (() async {
      try {
        return await _accept(
          await api.json(
            'POST',
            'auth/refresh',
            body: {'refresh_token': refresh},
          ),
          epoch,
        );
      } finally {
        if (epoch == _epoch) _renewing = null;
      }
    })();
  }

  Future<T> authorized<T>(Future<T> Function(String token) request) async {
    final epoch = _epoch;
    final token = await _token();
    late final T result;
    try {
      result = await request(token);
    } on ApiFailure catch (failure) {
      if (failure.status != 401 || epoch != _epoch) rethrow;
      result = await request(await _token(rejected: token));
    }
    if (epoch != _epoch) throw const ApiFailure(401, 'Phiên đã kết thúc.');
    return result;
  }

  Future<bool> logout() async {
    final access = _access, refresh = _refresh;
    await clear();
    try {
      if (access != null) {
        try {
          await api.json('POST', 'auth/logout', token: access);
          return true;
        } on ApiFailure catch (failure) {
          if (failure.status != 401) return false;
        }
      }
      if (refresh == null) return false;
      final next = await api.json(
        'POST',
        'auth/refresh',
        body: {'refresh_token': refresh},
      );
      await api.json(
        'POST',
        'auth/logout',
        token: next['access_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    _epoch++;
    userId = email = _access = _refresh = null;
    _expiry = 0;
    _remember = false;
    _renewing = null;
    await _storage.delete(key: storageKey);
  }
}

class OnlineScope extends InheritedWidget {
  const OnlineScope({super.key, required this.session, required super.child});
  final OnlineSession session;
  static OnlineSession? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnlineScope>()?.session;
  @override
  bool updateShouldNotify(OnlineScope oldWidget) =>
      session != oldWidget.session;
}
