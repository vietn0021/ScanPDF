import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scanpdf/online/api_client.dart';
import 'package:scanpdf/online/documents.dart';
import 'package:scanpdf/online/session_store.dart';
import 'package:scanpdf/scan_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
final base = Uri.parse('https://test.example/v1');

http.Response tokens(String user, String token, {bool expired = false}) =>
    http.Response(
      jsonEncode({
        'user': {'id': user, 'email': '$user@example.com'},
        'access_token': token,
        'refresh_token': 'refresh-$token',
        'expires_at':
            DateTime.now().millisecondsSinceEpoch ~/ 1000 +
            (expired ? -60 : 600),
      }),
      200,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('opens a remembered local library before contacting the API', () async {
    var requests = 0;
    final api = ScanApi(
      base,
      client: MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('login')) return tokens(a, 'access');
        throw http.ClientException('offline');
      }),
    );
    await OnlineSession(api).login('a@example.com', 'test', remember: true);
    final restored = OnlineSession(api);
    await restored.restore();
    expect(restored.owner, 'auth:$a');
    expect(requests, 1);
    await expectLater(
      restored.authorized((token) async => token),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 2);
    expect(restored.owner, 'auth:$a');
  });

  test(
    'refreshes once for simultaneous requests and stores only the rotated refresh token',
    () async {
      var refreshed = 0;
      final session = OnlineSession(
        ScanApi(
          base,
          client: MockClient((request) async {
            if (request.url.path.endsWith('login')) {
              return tokens(a, 'expired', expired: true);
            }
            refreshed++;
            expect(
              jsonDecode(request.body)['refresh_token'],
              'refresh-expired',
            );
            return tokens(a, 'next');
          }),
        ),
      );
      await session.login('a@example.com', 'test', remember: true);
      final results = await Future.wait(
        List.generate(3, (_) => session.authorized((token) async => token)),
      );
      expect(results, ['next', 'next', 'next']);
      expect(refreshed, 1);
      final data = jsonDecode(
        (await const FlutterSecureStorage().read(
          key: OnlineSession.storageKey,
        ))!,
      );
      expect(data['refresh'], 'refresh-next');
      expect(data.containsKey('access_token'), isFalse);
    },
  );

  test(
    'offline logout clears access and rejects a previous account response',
    () async {
      final inFlight = Completer<String>();
      final started = Completer<void>();
      final session = OnlineSession(
        ScanApi(
          base,
          client: MockClient((request) async {
            if (request.url.path.endsWith('login')) {
              return tokens(
                request.body.contains('b@example.com') ? b : a,
                'access',
              );
            }
            throw http.ClientException('offline');
          }),
        ),
      );
      await session.login('a@example.com', 'test', remember: true);
      final request = session.authorized((token) {
        started.complete();
        return inFlight.future;
      });
      final rejection = expectLater(request, throwsA(isA<ApiFailure>()));
      await started.future;
      expect(await session.logout(), isFalse);
      expect(session.owner, isNull);
      expect(
        await const FlutterSecureStorage().read(key: OnlineSession.storageKey),
        isNull,
      );
      await session.login('b@example.com', 'test', remember: false);
      expect(session.owner, 'auth:$b');
      inFlight.complete('private data');
      await rejection;
    },
  );

  testWidgets(
    'upload retries with the same ID after rebuilding and preserves local PDF',
    (tester) async {
      final keys = <String>[];
      final session = OnlineSession(
        ScanApi(
          base,
          client: MockClient((request) async {
            if (request.url.path.endsWith('login')) return tokens(a, 'access');
            keys.add(request.headers['idempotency-key']!);
            if (keys.length == 1) throw http.ClientException('offline');
            return http.Response('{"id":"cloud-1"}', 201);
          }),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final store = ScanStore(prefs, inMemory: true);
      final bytes = Uint8List.fromList([1, 2, 3]);
      const owner = 'auth:$a';
      final doc = await store.save(owner, 'Tai lieu', [bytes], bytes);
      await session.login('a@example.com', 'test', remember: false);
      Widget page(Key key) => MaterialApp(
        home: Scaffold(
          body: UploadControls(
            key: key,
            session: session,
            owner: owner,
            store: store,
            doc: doc,
          ),
        ),
      );
      await tester.pumpWidget(page(const ValueKey(1)));
      await tester.tap(find.text('Lưu trực tuyến'));
      await tester.pumpAndSettle();
      expect(find.text('Thử tải lại'), findsOneWidget);
      expect(await store.pdf(owner, doc), bytes);
      await tester.pumpWidget(page(const ValueKey(2)));
      await tester.tap(find.text('Lưu trực tuyến'));
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu trực tuyến'), findsOneWidget);
      expect(keys, hasLength(2));
      expect(keys.last, keys.first);
      expect(
        prefs.getString('scanpdf.upload.$owner.${doc.id}.cloudId'),
        'cloud-1',
      );
      expect(store.list('auth:$b'), isEmpty);
      expect(await store.pdf(owner, doc), bytes);
    },
  );

  testWidgets('cloud delete clears only the matching owner and upload ticket', (
    tester,
  ) async {
    const owner = 'auth:$a';
    const key = 'scanpdf.upload.$owner.local-1';
    const other = 'scanpdf.upload.auth:$b.local-2';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, ['ticket', 'Tai lieu.pdf']);
    await prefs.setBool('$key.ready', true);
    await prefs.setString('$key.cloudId', 'cloud-1');
    await prefs.setString('$other.cloudId', 'cloud-1');
    var deletes = 0;
    final session = OnlineSession(
      ScanApi(
        base,
        client: MockClient((request) async {
          if (request.url.path.endsWith('login')) return tokens(a, 'access');
          if (request.method == 'DELETE') {
            expect(request.url.path, '/v1/documents/cloud-1');
            deletes++;
            return http.Response('', 204);
          }
          return http.Response(
            '{"items":[{"id":"cloud-1","filename":"Tai lieu.pdf","page_count":1,"byte_size":3}],"next_cursor":null}',
            200,
          );
        }),
      ),
    );
    await session.login('a@example.com', 'test', remember: false);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudLibrary(session: session, owner: owner),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xóa PDF trực tuyến'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('Tai lieu.pdf'), findsNothing);
    expect(prefs.containsKey(key), isFalse);
    expect(prefs.containsKey('$key.ready'), isFalse);
    expect(prefs.containsKey('$key.cloudId'), isFalse);
    expect(prefs.getString('$other.cloudId'), 'cloud-1');
  });

  testWidgets('demo account does not get online upload access', (tester) async {
    final session = OnlineSession(
      ScanApi(base, client: MockClient((_) async => tokens(a, 'access'))),
    );
    await session.login('a@example.com', 'test', remember: false);
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineScope(
          session: session,
          child: Builder(
            builder: (context) => Text(
              accountSession(context, 'demo@scanpdf.local') == null
                  ? 'demo only'
                  : 'online',
            ),
          ),
        ),
      ),
    );
    expect(find.text('demo only'), findsOneWidget);
  });
}
