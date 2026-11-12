import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scanpdf/common.dart';
import 'package:scanpdf/account.dart';
import 'package:scanpdf/editor.dart';
import 'package:scanpdf/library.dart';
import 'package:scanpdf/main.dart';
import 'package:scanpdf/scan_data.dart';
import 'package:scanpdf/stitch_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List paper(int red, int green, int blue) {
  final canvas = img.Image(width: 48, height: 70);
  img.fill(canvas, color: img.ColorRgb8(red, green, blue));
  return img.encodeJpg(canvas);
}

Future<ScanStore> store() async {
  SharedPreferences.setMockInitialValues({});
  return ScanStore(await SharedPreferences.getInstance(), inMemory: true);
}

class _ThumbnailStore extends ScanStore {
  _ThumbnailStore(super.prefs) : super(inMemory: true);

  final reads = <String>[];
  final cover = paper(255, 255, 255);

  @override
  Future<Uint8List> page(String owner, SavedScan doc, int index) async {
    reads.add('$owner/${doc.id}/$index');
    return cover;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final grid in [false, true]) {
    testWidgets('${grid ? 'grid' : 'list'} reuses its thumbnail on rebuild', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = _ThumbnailStore(await SharedPreferences.getInstance());
      final doc = SavedScan(
        id: '1',
        name: 'Tài liệu',
        created: DateTime(2026),
        count: 1,
        size: 42,
      );

      Future<void> show(String owner, SavedScan doc) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 218,
                width: 300,
                child: grid
                    ? GridDocCard(
                        store: store,
                        owner: owner,
                        doc: doc,
                        onAction: (_) {},
                      )
                    : DocCard(
                        store: store,
                        owner: owner,
                        doc: doc,
                        onAction: (_) {},
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('a', doc);
      expect(find.byType(Image), findsOneWidget);
      await show('a', doc.rename('Tên mới'));
      expect(find.text('Tên mới.pdf'), findsOneWidget);
      expect(store.reads, ['a/1/0']);

      await show('b', doc);
      expect(store.reads, ['a/1/0', 'b/1/0']);
    });
  }

  testWidgets('startup shows the branded loader while ScanPDF opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: scanTheme(), home: const StartupScreen()),
    );
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Đang mở ScanPDF…'), findsOneWidget);
    expect(find.text('Có phiên mẫu'), findsNothing);
  });

  test('all 19 original Stitch frames are bundled', () async {
    expect(StitchFrame.values, hasLength(19));
    for (final frame in StitchFrame.values) {
      expect(
        (await rootBundle.load(frame.asset)).lengthInBytes,
        greaterThan(100),
      );
    }
  });

  test(
    'Letter export and preview storage are isolated from the real library',
    () async {
      final data = await store();
      final normal = ScanStore(data.prefs);
      final images = [paper(240, 240, 240)];
      final bytes = await makePdf(images, paper: PdfPaper.letter);
      expect(
        latin1.decode(bytes),
        matches(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+612\s+792\s*\]')),
      );
      await data.save(
        'sample',
        'Preview',
        images,
        bytes,
        paper: PdfPaper.letter,
      );
      await data.updateProfile('sample', 'Mẫu', null);
      expect(data.list('sample').single.paper, PdfPaper.letter);
      expect(normal.list('sample'), isEmpty);
      expect(normal.name('sample'), 'sample');
    },
  );

  testWidgets('profile and scan defaults are stored for the current account', (
    tester,
  ) async {
    await tester.view.resetForPhone();
    final data = await store();
    await data.signIn(demoOwner);
    await tester.pumpWidget(ScanPdfApp(store: data));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    final edit = find.text('Chỉnh sửa hồ sơ');
    await tester.scrollUntilVisible(edit, 160);
    await Scrollable.ensureVisible(tester.element(edit), alignment: .4);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Họ và tên'),
      'Người dùng mẫu',
    );
    final company = find.widgetWithText(
      TextFormField,
      'Công ty (không bắt buộc)',
    );
    await tester.ensureVisible(company);
    await tester.enterText(company, 'ScanPDF Lab');
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(data.name(demoOwner), 'Người dùng mẫu');
    expect(data.company(demoOwner), 'ScanPDF Lab');
    expect(data.company('other@example.com'), isEmpty);

    final quality = find.text('Chất lượng quét mặc định');
    await tester.scrollUntilVisible(quality, 160);
    await Scrollable.ensureVisible(tester.element(quality), alignment: .4);
    await tester.pumpAndSettle();
    await tester.tap(quality);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chất lượng cao'));
    await tester.pump();
    await tester.tap(find.text('Lưu cài đặt'));
    await tester.pumpAndSettle();
    expect(data.highQuality(demoOwner), isTrue);
    expect(data.highQuality('other@example.com'), isFalse);
    expect(tester.takeException(), isNull);
  });

  test(
    'PDF A4 is generated and library data is separated by account',
    () async {
      final data = await store();
      final pages = [
        paper(243, 80, 32),
        paper(32, 80, 243),
        paper(70, 243, 32),
      ];
      final bytes = await makePdf(pages);
      final structure = latin1.decode(bytes);
      expect(structure, startsWith('%PDF-'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(structure), hasLength(3));
      expect(structure, contains('/MediaBox'));
      final doc = await data.save('a@example.com', 'Ghi chú', pages, bytes);
      expect(data.list('a@example.com').single.filename, 'Ghi chú.pdf');
      expect(data.list('b@example.com'), isEmpty);
      await expectLater(data.pdf('b@example.com', doc), throwsException);
      expect(await data.page('a@example.com', doc, 1), pages[1]);
      final renamed = await data.rename('a@example.com', doc, 'Bài học');
      expect(data.list('a@example.com').single.filename, 'Bài học.pdf');
      expect(await data.pdf('a@example.com', renamed), bytes);
      await data.delete('a@example.com', renamed);
      expect(data.list('a@example.com'), isEmpty);
      await expectLater(data.pdf('a@example.com', renamed), throwsException);
    },
  );

  test(
    'perspective crop, rotation and grayscale change the exported image',
    () async {
      final page = ScanPage(
        paper(210, 70, 40),
        tone: Tone.gray,
        turns: 1,
        corners: const [
          Offset(.1, .12),
          Offset(.9, .08),
          Offset(.88, .9),
          Offset(.13, .86),
        ],
      );
      final result = img.decodeJpg(await renderPage(page))!;
      expect(result.width, greaterThan(result.height));
      expect(result.width, lessThan(70));
      final pixel = result.getPixel(result.width ~/ 2, result.height ~/ 2);
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    },
  );

  testWidgets('demo sign-in opens the library and offers photo sources', (
    tester,
  ) async {
    await tester.view.resetForPhone();
    final data = await store();
    await tester.pumpWidget(ScanPdfApp(store: data));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dùng tài khoản mẫu'));
    await tester.tap(find.text('Dùng tài khoản mẫu'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có tài liệu'), findsOneWidget);
    await tester.tap(find.text('Quét mới'));
    await tester.pumpAndSettle();
    expect(find.text('Chụp bằng camera'), findsOneWidget);
    expect(find.text('Chọn từ thư viện'), findsOneWidget);
    expect(find.text('Dùng tài liệu mẫu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page order is preserved through PDF export and return to library',
    (tester) async {
      await tester.view.resetForPhone();
      final data = await store();
      final pages = [
        ScanPage(paper(250, 50, 20)),
        ScanPage(paper(30, 50, 250)),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: scanTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => screen<void>(
                  context,
                  PagesScreen(store: data, owner: 'demo', initial: pages),
                ),
                child: const Text('Mở bản quét'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở bản quét'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tùy chọn trang 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Di chuyển về trước'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xuất PDF (2 trang)'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Tạo PDF'));
        final until = DateTime.now().add(const Duration(seconds: 12));
        while (data.list('demo').isEmpty && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Tài liệu đã sẵn sàng'), findsOneWidget);
      final saved = data.list('demo').single;
      final first = img
          .decodeJpg(await data.page('demo', saved, 0))!
          .getPixel(10, 10);
      expect(first.b, greaterThan(first.r));
      await tester.tap(find.text('Về thư viện'));
      // Export resumes outside the widget fake clock after its image isolates finish.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Mở bản quét'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

extension on TestFlutterView {
  Future<void> resetForPhone() async {
    physicalSize = const Size(390, 844);
    devicePixelRatio = 1;
    addTearDown(resetPhysicalSize);
    addTearDown(resetDevicePixelRatio);
  }
}
