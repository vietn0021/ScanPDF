import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

const fullCorners = [
  ui.Offset(0, 0),
  ui.Offset(1, 0),
  ui.Offset(1, 1),
  ui.Offset(0, 1),
];

enum Tone {
  color('Màu'),
  enhanced('Tăng cường'),
  gray('Xám'),
  mono('Đen trắng');

  const Tone(this.label);
  final String label;
}

class ScanPage {
  const ScanPage(
    this.bytes, {
    this.corners = fullCorners,
    this.tone = Tone.color,
    this.brightness = 0,
    this.contrast = 0,
    this.turns = 0,
  });
  final Uint8List bytes;
  final List<ui.Offset> corners;
  final Tone tone;
  final double brightness;
  final double contrast;
  final int turns;

  ScanPage copyWith({
    List<ui.Offset>? corners,
    Tone? tone,
    double? brightness,
    double? contrast,
    int? turns,
  }) => ScanPage(
    bytes,
    corners: corners ?? this.corners,
    tone: tone ?? this.tone,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    turns: turns ?? this.turns,
  );
}

Future<Uint8List> normalizePhoto(Uint8List bytes) => compute(_normalize, bytes);
Uint8List _normalize(Uint8List bytes) {
  var source = img.decodeImage(bytes);
  if (source == null) throw const FormatException('Ảnh không hợp lệ');
  source = img.bakeOrientation(source);
  if (math.max(source.width, source.height) > 2400) {
    source = source.width >= source.height
        ? img.copyResize(source, width: 2400)
        : img.copyResize(source, height: 2400);
  }
  return img.encodeJpg(source, quality: 94);
}

bool validCorners(List<ui.Offset> c) {
  for (var i = 0; i < 4; i++) {
    final a = c[(i + 1) % 4] - c[i], b = c[(i + 2) % 4] - c[(i + 1) % 4];
    if (a.dx * b.dy - a.dy * b.dx <= .006) return false;
  }
  return true;
}

Future<List<ui.Offset>?> detectPaper(Uint8List bytes) =>
    compute(_detect, bytes);
List<ui.Offset>? _detect(Uint8List bytes) {
  final original = img.decodeJpg(bytes);
  if (original == null) return null;
  final small = img.copyResize(original, width: math.min(160, original.width));
  final w = small.width, h = small.height;
  if (w < 16 || h < 16) return null;
  final edge = <num>[];
  for (var i = 0; i < w; i += 4) {
    edge.add(small.getPixel(i, 0).luminance);
    edge.add(small.getPixel(i, h - 1).luminance);
  }
  for (var i = 0; i < h; i += 4) {
    edge.add(small.getPixel(0, i).luminance);
    edge.add(small.getPixel(w - 1, i).luminance);
  }
  edge.sort();
  final threshold = math.max(157, edge[(edge.length * .75).floor()] + 25);
  if (threshold > 245) return null;
  final candidates = <ui.Offset>[];
  for (var y = 2; y < h - 2; y++) {
    for (var x = 2; x < w - 2; x++) {
      if (small.getPixel(x, y).luminance > threshold &&
          small.getPixel(x - 2, y).luminance > threshold &&
          small.getPixel(x + 2, y).luminance > threshold &&
          small.getPixel(x, y - 2).luminance > threshold &&
          small.getPixel(x, y + 2).luminance > threshold) {
        candidates.add(ui.Offset(x / (w - 1), y / (h - 1)));
      }
    }
  }
  if (candidates.length < w * h * .19) return null;
  ui.Offset pick(double Function(ui.Offset) score) =>
      candidates.reduce((a, b) => score(a) < score(b) ? a : b);
  final c = [
    pick((p) => p.dx + p.dy),
    pick((p) => -p.dx + p.dy),
    pick((p) => -p.dx - p.dy),
    pick((p) => p.dx - p.dy),
  ];
  if (!validCorners(c) ||
      (c[1] - c[0]).distance < .4 ||
      (c[3] - c[0]).distance < .4) {
    return null;
  }
  return c;
}

typedef RenderArgs = ({ScanPage page, int maxSide, int quality});
Future<Uint8List> renderPage(
  ScanPage page, {
  int maxSide = 1250,
  int quality = 88,
}) => compute(_render, (page: page, maxSide: maxSide, quality: quality));

Uint8List _render(RenderArgs args) {
  final p = args.page;
  var source = img.decodeJpg(p.bytes);
  if (source == null) throw const FormatException('Ảnh không hợp lệ');
  final c = p.corners;
  if (!listEquals(c, fullCorners) && validCorners(c)) {
    final points = c
        .map(
          (o) =>
              ui.Offset(o.dx * (source!.width - 1), o.dy * (source.height - 1)),
        )
        .toList();
    final [a, b, d, e] = points;
    final width = math.max((b - a).distance, (d - e).distance);
    final height = math.max((e - a).distance, (d - b).distance);
    final factor = math.min(1.0, args.maxSide / math.max(width, height));
    final output = img.Image(
      width: math.max(2, (width * factor).round()),
      height: math.max(2, (height * factor).round()),
    );
    final dx1 = b.dx - d.dx, dx2 = e.dx - d.dx, dx3 = a.dx - b.dx + d.dx - e.dx;
    final dy1 = b.dy - d.dy, dy2 = e.dy - d.dy, dy3 = a.dy - b.dy + d.dy - e.dy;
    final determinant = dx1 * dy2 - dx2 * dy1;
    final g = determinant.abs() < 1e-8
        ? 0.0
        : (dx3 * dy2 - dx2 * dy3) / determinant;
    final h = determinant.abs() < 1e-8
        ? 0.0
        : (dx1 * dy3 - dx3 * dy1) / determinant;
    for (final pixel in output) {
      final u = pixel.x / (output.width - 1), v = pixel.y / (output.height - 1);
      final den = 1 + g * u + h * v;
      final x =
          (a.dx + (b.dx - a.dx + g * b.dx) * u + (e.dx - a.dx + h * e.dx) * v) /
          den;
      final y =
          (a.dy + (b.dy - a.dy + g * b.dy) * u + (e.dy - a.dy + h * e.dy) * v) /
          den;
      pixel.set(
        source.getPixel(
          x.round().clamp(0, source.width - 1),
          y.round().clamp(0, source.height - 1),
        ),
      );
    }
    source = output;
  } else if (math.max(source.width, source.height) > args.maxSide) {
    source = source.width >= source.height
        ? img.copyResize(source, width: args.maxSide)
        : img.copyResize(source, height: args.maxSide);
  }
  if (p.turns % 4 != 0) {
    source = img.copyRotate(source, angle: (p.turns % 4) * 90);
  }
  if (p.tone != Tone.color || p.brightness != 0 || p.contrast != 0) {
    int adjust(num v) =>
        ((v - 128) *
                    (1 +
                        p.contrast * .85 +
                        (p.tone == Tone.enhanced ? .18 : 0)) +
                128 +
                p.brightness * 95 +
                (p.tone == Tone.enhanced ? 12 : 0))
            .round()
            .clamp(0, 255);
    for (final pixel in source) {
      if (p.tone == Tone.color || p.tone == Tone.enhanced) {
        pixel.setRgb(adjust(pixel.r), adjust(pixel.g), adjust(pixel.b));
      } else {
        final value = adjust(pixel.luminance);
        final gray = p.tone == Tone.mono ? (value > 157 ? 255 : 0) : value;
        pixel.setRgb(gray, gray, gray);
      }
    }
  }
  return img.encodeJpg(source, quality: args.quality);
}

enum PdfPaper {
  a4('A4', '210 × 297 mm'),
  letter('Letter', '8.5 × 11 in'),
  original('Khổ gốc', 'Theo tỷ lệ ảnh');

  const PdfPaper(this.label, this.detail);
  final String label, detail;
}

Future<Uint8List> makePdf(
  List<Uint8List> pages, {
  PdfPaper paper = PdfPaper.a4,
}) => compute(_pdf, (pages: pages, paper: paper));
Future<Uint8List> _pdf(({List<Uint8List> pages, PdfPaper paper}) input) {
  final pages = input.pages;
  if (pages.isEmpty) throw const FormatException('Tài liệu không có trang');
  final document = pw.Document(creator: 'ScanPDF');
  for (final bytes in pages) {
    final picture = pw.MemoryImage(bytes);
    final format = switch (input.paper) {
      PdfPaper.a4 => PdfPageFormat.a4,
      PdfPaper.letter => PdfPageFormat.letter,
      PdfPaper.original => _originalFormat(bytes),
    };
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(input.paper == PdfPaper.original ? 0 : 18),
        build: (_) =>
            pw.Center(child: pw.Image(picture, fit: pw.BoxFit.contain)),
      ),
    );
  }
  return document.save();
}

PdfPageFormat _originalFormat(Uint8List bytes) {
  final image = img.decodeJpg(bytes);
  if (image == null) throw const FormatException('Ảnh PDF không hợp lệ');
  final scale = PdfPageFormat.a4.height / math.max(image.width, image.height);
  return PdfPageFormat(image.width * scale, image.height * scale);
}

class SavedScan {
  const SavedScan({
    required this.id,
    required this.name,
    required this.created,
    required this.count,
    required this.size,
    this.paper = PdfPaper.a4,
  });
  final String id, name;
  final DateTime created;
  final int count, size;
  final PdfPaper paper;
  String get filename => '$name.pdf';
  SavedScan rename(String value) => SavedScan(
    id: id,
    name: value,
    created: created,
    count: count,
    size: size,
    paper: paper,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': created.toIso8601String(),
    'count': count,
    'size': size,
    'paper': paper.name,
  };
  factory SavedScan.fromJson(Map<String, dynamic> j) => SavedScan(
    id: j['id'],
    name: j['name'],
    created: DateTime.parse(j['date']),
    count: j['count'],
    size: j['size'],
    paper: PdfPaper.values.firstWhere(
      (paper) => paper.name == j['paper'],
      orElse: () => PdfPaper.a4,
    ),
  );
}

class ScanStore {
  ScanStore(this.prefs, {this.inMemory = false});
  final SharedPreferences prefs;
  final bool inMemory;
  final Map<String, Uint8List> _memory = {};
  final Map<String, List<SavedScan>> _memoryIndex = {};
  final Map<String, Object> _memoryProfile = {};
  String? get account => prefs.getString('session');
  Future<void> signIn(String account) async {
    await prefs.setString('session', account);
  }

  Future<void> signOut() async {
    await prefs.remove('session');
  }

  String _profile(String owner, String field) => 'profile:$owner:$field';
  String? _readProfile(String key) =>
      inMemory ? _memoryProfile[key] as String? : prefs.getString(key);
  Future<void> _writeProfile(String key, String value) async {
    if (inMemory) {
      _memoryProfile[key] = value;
    } else if (!await prefs.setString(key, value)) {
      throw const FileSystemException('Không thể lưu hồ sơ');
    }
  }

  String name(String owner, {String? email}) =>
      _readProfile(_profile(owner, 'name')) ??
      (owner == 'demo@scanpdf.local'
          ? 'Tài khoản mẫu'
          : (email ?? owner).split('@').first);
  String? avatar(String owner) => _readProfile(_profile(owner, 'avatar'));
  String phone(String owner) => _readProfile(_profile(owner, 'phone')) ?? '';
  String company(String owner) =>
      _readProfile(_profile(owner, 'company')) ?? '';
  bool highQuality(String owner) =>
      (inMemory
          ? _memoryProfile[_profile(owner, 'highQuality')] as bool?
          : prefs.getBool(_profile(owner, 'highQuality'))) ??
      false;
  Future<void> setHighQuality(String owner, bool value) async {
    if (inMemory) {
      _memoryProfile[_profile(owner, 'highQuality')] = value;
      return;
    }
    if (!await prefs.setBool(_profile(owner, 'highQuality'), value)) {
      throw const FileSystemException('Không thể lưu cài đặt quét');
    }
  }

  Future<void> updateProfile(
    String owner,
    String name,
    Uint8List? avatar, {
    String? phone,
    String? company,
  }) async {
    await _writeProfile(_profile(owner, 'name'), name);
    if (phone != null) await _writeProfile(_profile(owner, 'phone'), phone);
    if (company != null) {
      await _writeProfile(_profile(owner, 'company'), company);
    }
    if (avatar != null) {
      await _writeProfile(_profile(owner, 'avatar'), base64Encode(avatar));
    }
  }

  String _index(String owner) => 'docs:$owner';
  List<SavedScan> list(String owner) => inMemory
      ? List.of(_memoryIndex[owner] ?? [])
      : (prefs.getStringList(_index(owner)) ?? [])
            .map((s) => SavedScan.fromJson(jsonDecode(s)))
            .toList();
  Future<void> _writeList(String owner, List<SavedScan> items) async {
    if (inMemory) {
      _memoryIndex[owner] = List.of(items);
      return;
    }
    if (!await prefs.setStringList(
      _index(owner),
      items.map((d) => jsonEncode(d.toJson())).toList(),
    )) {
      throw const FileSystemException('Không thể lưu thư viện');
    }
  }

  String _key(String owner, SavedScan doc, String name) =>
      'scanpdf-${base64Url.encode(utf8.encode(owner))}-${doc.id}-$name';
  Future<File> _file(String key) async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$key');
  Future<void> _write(String key, Uint8List bytes) async {
    if (inMemory) {
      _memory[key] = bytes;
    } else if (kIsWeb) {
      if (!await prefs.setString(key, base64Encode(bytes))) {
        throw const FileSystemException('Không thể lưu tệp');
      }
    } else {
      await (await _file(key)).writeAsBytes(bytes, flush: true);
    }
  }

  Future<Uint8List> _read(String key) async {
    if (inMemory) {
      return _memory[key] ??
          (throw const FileSystemException('Tệp không tồn tại'));
    }
    if (kIsWeb) {
      return base64Decode(
        prefs.getString(key) ??
            (throw const FileSystemException('Tệp không tồn tại')),
      );
    }
    return (await _file(key)).readAsBytes();
  }

  Future<void> _remove(String key) async {
    if (inMemory) {
      _memory.remove(key);
    } else if (kIsWeb) {
      await prefs.remove(key);
    } else {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    }
  }

  Future<Uint8List> pdf(String owner, SavedScan doc) =>
      _read(_key(owner, doc, 'document.pdf'));
  Future<Uint8List> page(String owner, SavedScan doc, int index) =>
      _read(_key(owner, doc, 'page-$index.jpg'));
  Future<SavedScan> save(
    String owner,
    String name,
    List<Uint8List> pages,
    Uint8List pdf, {
    PdfPaper paper = PdfPaper.a4,
  }) async {
    final now = DateTime.now();
    final doc = SavedScan(
      id: '${now.microsecondsSinceEpoch}',
      name: name,
      created: now,
      count: pages.length,
      size: pdf.length,
      paper: paper,
    );
    final keys = [
      _key(owner, doc, 'document.pdf'),
      for (var i = 0; i < pages.length; i++) _key(owner, doc, 'page-$i.jpg'),
    ];
    try {
      await _write(keys.first, pdf);
      for (var i = 0; i < pages.length; i++) {
        await _write(keys[i + 1], pages[i]);
      }
      await _writeList(owner, [doc, ...list(owner)]);
    } catch (_) {
      for (final key in keys) {
        try {
          await _remove(key);
        } catch (_) {}
      }
      rethrow;
    }
    return doc;
  }

  Future<SavedScan> rename(String owner, SavedScan doc, String name) async {
    final renamed = doc.rename(name);
    await _writeList(
      owner,
      list(owner).map((d) => d.id == doc.id ? renamed : d).toList(),
    );
    return renamed;
  }

  Future<void> delete(String owner, SavedScan doc) async {
    for (var i = 0; i < doc.count; i++) {
      await _remove(_key(owner, doc, 'page-$i.jpg'));
    }
    await _remove(_key(owner, doc, 'document.pdf'));
    await _writeList(owner, list(owner).where((d) => d.id != doc.id).toList());
  }
}

String fileSize(int size) => size >= 1024 * 1024
    ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
    : '${(size / 1024).ceil()} KB';

Future<List<ScanPage>> samplePages() async {
  final result = <ScanPage>[];
  for (var i = 0; i < 3; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..color = const ui.Color(0xfffcfcf8);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 640, 880), paint);
    void label(
      String text,
      double x,
      double y,
      double size,
      ui.Color color, {
      bool bold = false,
    }) {
      final b =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: 'Roboto',
                fontSize: size,
                fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
              ),
            )
            ..pushStyle(ui.TextStyle(color: color))
            ..addText(text);
      final p = b.build()..layout(const ui.ParagraphConstraints(width: 540));
      canvas.drawParagraph(p, ui.Offset(x, y));
    }

    const dark = ui.Color(0xff1c2535), red = ui.Color(0xffb81c29);
    label('SCANPDF  /  TÀI LIỆU MẪU', 52, 52, 17, red, bold: true);
    label(
      ['Ghi chú môn học', 'Ví dụ thực hành', 'Tóm tắt bài học'][i],
      52,
      93,
      38,
      dark,
      bold: true,
    );
    label('Số hóa tài liệu và quản lý thông tin', 52, 152, 19, dark);
    paint.color = const ui.Color(0xffdedede);
    canvas.drawRect(const ui.Rect.fromLTWH(52, 199, 530, 2), paint);
    for (var k = 0; k < 4; k++) {
      label(
        '${k + 1}. ${['Chuẩn bị tài liệu', 'Xử lý hình ảnh', 'Sắp xếp nội dung', 'Lưu và chia sẻ'][k]}',
        52,
        227 + k * 139,
        22,
        dark,
        bold: true,
      );
      label(
        'Kiểm tra chất lượng và thứ tự trước khi lưu.',
        52,
        267 + k * 139,
        17,
        dark,
      );
      label(
        'Ghi chú minh họa dùng trong bản trải nghiệm.',
        52,
        299 + k * 139,
        17,
        dark,
      );
    }
    label('TRANG ${i + 1} / 3', 52, 819, 15, red, bold: true);
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 880);
    picture.dispose();
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    result.add(ScanPage(await normalizePhoto(data.buffer.asUint8List())));
  }
  return result;
}
