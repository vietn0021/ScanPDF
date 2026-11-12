import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_screen.dart';
import 'common.dart';
import 'design_preview.dart';
import 'library.dart';
import 'online/documents.dart';
import 'scan_data.dart';

enum _Source { camera, gallery, sample }

const maxPages = 50;

Future<List<ScanPage>> choosePages(
  BuildContext context, {
  bool allowSample = false,
  int room = maxPages,
}) async {
  if (room <= 0) {
    notice(context, 'Mỗi tài liệu tối đa 50 trang.');
    return [];
  }
  final source = await showModalBottomSheet<_Source>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SectionTitle(
              'Thêm tài liệu mới',
              subtitle: 'Chọn cách đưa giấy tờ vào ScanPDF.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: red),
            title: const Text('Chụp bằng camera'),
            subtitle: const Text('Quét một hoặc nhiều trang'),
            onTap: () => Navigator.pop(ctx, _Source.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: red),
            title: const Text('Chọn từ thư viện'),
            subtitle: const Text('Chọn một hoặc nhiều ảnh'),
            onTap: () => Navigator.pop(ctx, _Source.gallery),
          ),
          if (allowSample)
            ListTile(
              leading: const Icon(Icons.description_outlined, color: red),
              title: const Text('Dùng tài liệu mẫu'),
              subtitle: const Text('Thử với 3 trang có sẵn'),
              onTap: () => Navigator.pop(ctx, _Source.sample),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return [];
  try {
    if (source == _Source.camera) {
      final pages = await screen<List<ScanPage>>(context, const CameraScreen());
      return pages?.take(room).toList() ?? [];
    }
    if (source == _Source.sample) {
      return (await samplePages()).take(room).toList();
    }
    final selected = await ImagePicker().pickMultiImage(
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    final pages = <ScanPage>[];
    var skipped = 0;
    for (final file in selected.take(room)) {
      try {
        pages.add(ScanPage(await normalizePhoto(await file.readAsBytes())));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0 && context.mounted) {
      notice(context, 'Không thể mở $skipped ảnh đã chọn.');
    }
    return pages;
  } catch (_) {
    if (context.mounted) {
      notice(context, 'Không thể thêm ảnh. Vui lòng thử lại.');
    }
    return [];
  }
}

enum _PageAction { crop, edit, left, right, delete }

class PagesScreen extends StatefulWidget {
  const PagesScreen({
    super.key,
    required this.store,
    required this.owner,
    required this.initial,
  });
  final ScanStore store;
  final String owner;
  final List<ScanPage> initial;
  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  late final pages = widget.initial.take(maxPages).toList();
  bool loading = false, saved = false;

  Future<void> add() async {
    if (loading) return;
    setState(() => loading = true);
    final added = await choosePages(context, room: maxPages - pages.length);
    if (mounted) {
      setState(() {
        pages.addAll(added);
        loading = false;
      });
    }
  }

  Future<void> action(int i, _PageAction action) async {
    switch (action) {
      case _PageAction.crop:
        final result = await screen<ScanPage>(
          context,
          CropScreen(page: pages[i], index: i, count: pages.length),
        );
        if (result != null && mounted) setState(() => pages[i] = result);
      case _PageAction.edit:
        final result = await screen<ScanPage>(
          context,
          FilterScreen(
            page: pages[i],
            index: i,
            count: pages.length,
            onBatch: (filter) => setState(() {
              for (var j = 0; j < pages.length; j++) {
                if (j == i) continue;
                pages[j] = pages[j].copyWith(
                  tone: filter.tone,
                  brightness: filter.brightness,
                  contrast: filter.contrast,
                );
              }
            }),
          ),
        );
        if (result != null && mounted) setState(() => pages[i] = result);
      case _PageAction.left:
        move(i, i - 1);
      case _PageAction.right:
        move(i, i + 1);
      case _PageAction.delete:
        if (await confirm(
              context,
              title: 'Xóa trang ${i + 1}?',
              detail: 'Trang này sẽ không có trong PDF.',
              accept: 'Xóa trang',
            ) &&
            mounted) {
          setState(() => pages.removeAt(i));
        }
    }
  }

  void move(int from, int to) {
    if (from != to &&
        from >= 0 &&
        from < pages.length &&
        to >= 0 &&
        to < pages.length) {
      setState(() => pages.insert(to, pages.removeAt(from)));
    }
  }

  Future<void> export() async {
    final done = await screen<bool>(
      context,
      ExportScreen(
        store: widget.store,
        owner: widget.owner,
        pages: List.of(pages),
      ),
    );
    if (done == true && mounted) {
      saved = true;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved || pages.isEmpty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await confirm(
            context,
            title: 'Bỏ bản quét này?',
            detail: 'Các trang chưa xuất PDF sẽ không được lưu.',
            accept: 'Bỏ bản quét',
            cancel: 'Tiếp tục chỉnh sửa',
          ) &&
          context.mounted) {
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Sắp xếp trang')),
      body: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: SectionTitle(
                    'Tài liệu mới',
                    subtitle: '${pages.length} trang • Kéo giữ để đổi thứ tự',
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Thêm trang',
                  onPressed: loading ? null : add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InfoStrip(
                    icon: Icons.touch_app_outlined,
                    text: 'Mẹo: Chạm giữ và kéo ảnh để đổi thứ tự các trang.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.rotate_right),
                        label: const Text('Xoay tất cả'),
                        onPressed: () => setState(() {
                          for (var i = 0; i < pages.length; i++) {
                            pages[i] = pages[i].copyWith(
                              turns: pages[i].turns + 1,
                            );
                          }
                        }),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.tune),
                        label: const Text('Bộ lọc màu'),
                        onPressed: () => action(0, _PageAction.edit),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: pages.isEmpty
                ? StatePanel(
                    icon: Icons.note_add_outlined,
                    title: 'Chưa có trang nào',
                    message: 'Thêm ảnh để bắt đầu tạo PDF.',
                    action: OutlinedButton(
                      onPressed: loading ? null : add,
                      child: const Text('Thêm trang'),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 226,
                          mainAxisExtent: 238,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: pages.length + 1,
                    itemBuilder: (context, i) {
                      if (i == pages.length) {
                        return OutlinedButton(
                          onPressed: loading ? null : add,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add),
                              SizedBox(height: 8),
                              Text('Thêm trang'),
                            ],
                          ),
                        );
                      }
                      final page = pages[i];
                      return DragTarget<int>(
                        onWillAcceptWithDetails: (d) => d.data != i,
                        onAcceptWithDetails: (d) => move(d.data, i),
                        builder: (context, candidates, _) =>
                            LongPressDraggable<int>(
                              data: i,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: 122,
                                  height: 150,
                                  child: Image.memory(
                                    page.bytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              childWhenDragging: const DecoratedBox(
                                decoration: BoxDecoration(color: mist),
                              ),
                              child: Panel(
                                padding: EdgeInsets.zero,
                                borderColor: candidates.isNotEmpty ? red : line,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () =>
                                            action(i, _PageAction.crop),
                                        child: SizedBox.expand(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: PageThumbnail(page: page),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Trang ${i + 1}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Chỉnh ảnh trang ${i + 1}',
                                            onPressed: () =>
                                                action(i, _PageAction.edit),
                                            icon: const Icon(
                                              Icons.tune,
                                              size: 19,
                                            ),
                                          ),
                                          PopupMenuButton<_PageAction>(
                                            tooltip: 'Tùy chọn trang ${i + 1}',
                                            onSelected: (a) => action(i, a),
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: _PageAction.crop,
                                                child: Text('Cắt viền'),
                                              ),
                                              const PopupMenuItem(
                                                value: _PageAction.edit,
                                                child: Text('Chỉnh ảnh'),
                                              ),
                                              if (i > 0)
                                                const PopupMenuItem(
                                                  value: _PageAction.left,
                                                  child: Text(
                                                    'Di chuyển về trước',
                                                  ),
                                                ),
                                              if (i + 1 < pages.length)
                                                const PopupMenuItem(
                                                  value: _PageAction.right,
                                                  child: Text(
                                                    'Di chuyển về sau',
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: _PageAction.delete,
                                                child: Text('Xóa trang'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: CommandBar(
        child: FilledButton.icon(
          onPressed: pages.isEmpty || loading ? null : export,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text('Xuất PDF (${pages.length} trang)'),
        ),
      ),
    ),
  );
}

class PageThumbnail extends StatefulWidget {
  const PageThumbnail({super.key, required this.page});
  final ScanPage page;
  @override
  State<PageThumbnail> createState() => _PageThumbnailState();
}

class _Limiter {
  final _waiting = Queue<Completer<void>>();
  int _running = 0;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running < 2) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.addLast(turn);
      await turn.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isEmpty) {
        _running--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

class _PageThumbnailState extends State<PageThumbnail> {
  static final _limiter = _Limiter();
  late Future<Uint8List> preview = _render(widget.page);

  Future<Uint8List> _render(ScanPage page) =>
      _limiter.run(() => renderPage(page, maxSide: 300));

  @override
  void didUpdateWidget(PageThumbnail old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      preview = _render(widget.page);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: preview,
    builder: (_, s) => Image.memory(
      s.data ?? widget.page.bytes,
      fit: BoxFit.contain,
      cacheWidth: 320,
      gaplessPlayback: true,
    ),
  );
}

class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.page,
    required this.index,
    required this.count,
  });
  final ScanPage page;
  final int index, count;
  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late List<Offset> corners = List.of(widget.page.corners);
  late final aspect = _aspect();
  bool busy = false, changed = false;
  int rotation = 0;

  List<Offset> rotateCorners(List<Offset> points, int steps) {
    var rotated = points;
    for (var i = 0; i < steps % 4; i++) {
      rotated = [
        for (final index in [3, 0, 1, 2])
          Offset(1 - rotated[index].dy, rotated[index].dx),
      ];
    }
    return rotated;
  }

  Future<double> _aspect() async {
    final codec = await ui.instantiateImageCodec(widget.page.bytes);
    final frame = await codec.getNextFrame();
    final ratio = frame.image.width / frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return ratio;
  }

  Future<void> detect() async {
    setState(() => busy = true);
    try {
      final result = await detectPaper(widget.page.bytes);
      if (!mounted) return;
      if (result == null) {
        notice(
          context,
          'Không tìm thấy mép giấy. Kéo 4 góc để chọn vùng tài liệu.',
        );
      } else {
        setState(() {
          corners = rotateCorners(result, rotation);
          changed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        notice(context, 'Không thể tự nhận diện. Bạn vẫn có thể chỉnh tay.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: scanTheme(dark: true),
    child: Builder(
      builder: (context) => PopScope(
        canPop: !changed,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirm(
                context,
                title: 'Bỏ vùng cắt vừa chỉnh?',
                detail: 'Trang sẽ giữ vùng cắt trước đó.',
                accept: 'Bỏ thay đổi',
                cancel: 'Chỉnh tiếp',
              ) &&
              context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Cắt viền & nắn góc'),
            actions: [
              IconButton(
                tooltip: 'Xoay 90 độ',
                icon: const Icon(Icons.rotate_right),
                onPressed: busy
                    ? null
                    : () => setState(() {
                        corners = rotateCorners(corners, 1);
                        rotation = (rotation + 1) % 4;
                        changed = true;
                      }),
              ),
              IconButton(
                tooltip: 'Đặt lại vùng cắt',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        corners = List.of(fullCorners);
                        rotation = 0;
                        changed = true;
                      }),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Trang ${widget.index + 1} / ${widget.count} • Kéo 4 góc để chỉnh',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FutureBuilder<double>(
                    future: aspect,
                    builder: (context, s) {
                      if (s.hasError) {
                        return const StatePanel(
                          icon: Icons.broken_image_outlined,
                          title: 'Không mở được ảnh',
                          message: 'Quay lại và chọn ảnh khác.',
                        );
                      }
                      if (!s.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Center(
                        child: AspectRatio(
                          aspectRatio: rotation.isOdd ? 1 / s.data! : s.data!,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final size = box.biggest;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: RotatedBox(
                                      quarterTurns: rotation,
                                      child: Image.memory(
                                        widget.page.bytes,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _CropOverlay(corners),
                                      ),
                                    ),
                                  ),
                                  for (var i = 0; i < 4; i++)
                                    Positioned(
                                      left: corners[i].dx * size.width - 24,
                                      top: corners[i].dy * size.height - 24,
                                      width: 48,
                                      height: 48,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanUpdate: (detail) {
                                          if (busy) return;
                                          final current = corners[i];
                                          final next = List<Offset>.of(corners)
                                            ..[i] = Offset(
                                              (current.dx +
                                                      detail.delta.dx /
                                                          size.width)
                                                  .clamp(0.0, 1.0),
                                              (current.dy +
                                                      detail.delta.dy /
                                                          size.height)
                                                  .clamp(0.0, 1.0),
                                            );
                                          if (validCorners(next)) {
                                            setState(() {
                                              corners = next;
                                              changed = true;
                                            });
                                          }
                                        },
                                        child: Center(
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: red,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: CommandBar(
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : detect,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(busy ? 'Đang dò…' : 'Tự động'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: busy
                        ? null
                        : () => Navigator.pop(
                            context,
                            widget.page.copyWith(
                              corners: rotateCorners(
                                List.of(corners),
                                4 - rotation,
                              ),
                              turns: widget.page.turns + rotation,
                            ),
                          ),
                    child: const Text('Áp dụng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CropOverlay extends CustomPainter {
  const _CropOverlay(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addPolygon(
        points
            .map((p) => Offset(p.dx * size.width, p.dy * size.height))
            .toList(),
        true,
      );
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawPath(
      path,
      Paint()
        ..color = red
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CropOverlay old) => !identical(points, old.points);
}

class FilterScreen extends StatefulWidget {
  const FilterScreen({
    super.key,
    required this.page,
    required this.index,
    required this.count,
    this.onBatch,
  });
  final ScanPage page;
  final int index, count;
  final ValueChanged<ScanPage>? onBatch;
  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late ScanPage page = widget.page;
  late Future<Uint8List> preview = renderPage(page, maxSide: 900);
  Timer? debounce;
  bool applyAll = false;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void update(ScanPage value) {
    setState(() => page = value);
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => preview = renderPage(page, maxSide: 900));
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: scanTheme(dark: true),
    child: Builder(
      builder: (context) => PopScope(
        canPop: identical(page, widget.page),
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirm(
                context,
                title: 'Bỏ thay đổi chưa áp dụng?',
                detail: 'Ảnh trước khi chỉnh sẽ được giữ nguyên.',
                accept: 'Bỏ thay đổi',
                cancel: 'Chỉnh tiếp',
              ) &&
              context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Chỉnh ảnh'),
            actions: [
              IconButton(
                tooltip: 'Xoay 90 độ',
                onPressed: () => update(page.copyWith(turns: page.turns + 1)),
                icon: const Icon(Icons.rotate_right),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Trang ${widget.index + 1} / ${widget.count}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: FutureBuilder<Uint8List>(
                    future: preview,
                    builder: (_, s) {
                      if (s.hasError) {
                        return const StatePanel(
                          icon: Icons.broken_image_outlined,
                          title: 'Không thể xem trước',
                          message: 'Quay lại và chọn ảnh khác.',
                        );
                      }
                      return s.hasData
                          ? Center(
                              child: Image.memory(
                                s.data!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            )
                          : const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Bộ lọc màu tối ưu',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final value in Tone.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(value.label),
                                selected: page.tone == value,
                                onSelected: (_) =>
                                    update(page.copyWith(tone: value)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Độ sáng   ${(page.brightness * 100).round()}%',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Slider(
                      value: page.brightness,
                      min: -1,
                      max: 1,
                      onChanged: (v) => update(page.copyWith(brightness: v)),
                    ),
                    Text(
                      'Độ tương phản   ${(page.contrast * 100).round()}%',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Slider(
                      value: page.contrast,
                      min: -1,
                      max: 1,
                      onChanged: (v) => update(page.copyWith(contrast: v)),
                    ),
                    if (widget.count > 1 && widget.onBatch != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'Áp dụng bộ lọc cho tất cả ${widget.count} trang',
                        ),
                        value: applyAll,
                        onChanged: (value) => setState(() => applyAll = value),
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: CommandBar(
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => update(
                    page.copyWith(
                      tone: Tone.color,
                      brightness: 0,
                      contrast: 0,
                      turns: 0,
                    ),
                  ),
                  child: const Text('Đặt lại'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (applyAll) widget.onBatch?.call(page);
                      Navigator.pop(context, page);
                    },
                    child: const Text('Áp dụng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.store,
    required this.owner,
    required this.pages,
  });
  final ScanStore store;
  final String owner;
  final List<ScanPage> pages;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final name = TextEditingController(text: 'Ghi chú môn học');
  final form = GlobalKey<FormState>();
  late bool high = widget.store.highQuality(widget.owner);
  PdfPaper paper = PdfPaper.a4;
  bool busy = false, compress = true, cancelling = false, writing = false;
  String? error;
  int progress = 0;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (busy || !form.currentState!.validate()) return;
    final filename = bareName(name.text);
    setState(() {
      busy = true;
      error = null;
      progress = 0;
      cancelling = false;
      writing = false;
    });
    SavedScan doc;
    try {
      final images = <Uint8List>[];
      for (final page in widget.pages) {
        images.add(
          await renderPage(
            page,
            maxSide: high ? 2400 : 1650,
            quality: compress ? (high ? 91 : 76) : 97,
          ),
        );
        if (!mounted) return;
        if (cancelling) {
          setState(() => busy = false);
          return;
        }
        if (mounted) setState(() => progress = images.length);
      }
      final pdf = await makePdf(images, paper: paper);
      if (!mounted) return;
      if (cancelling) {
        setState(() => busy = false);
        return;
      }
      setState(() => writing = true);
      doc = await widget.store.save(
        widget.owner,
        filename,
        images,
        pdf,
        paper: paper,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = writing
              ? 'Không thể lưu PDF trên máy. Kiểm tra dung lượng rồi thử lại.'
              : 'Không thể tạo PDF. Kiểm tra các trang ảnh hoặc thử lại.';
        });
      }
      return;
    }
    if (!mounted) return;
    await screen<void>(
      context,
      SavedResult(store: widget.store, owner: widget.owner, doc: doc),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          busy ? '${bareName(name.text)}.pdf' : 'Xuất & lưu PDF',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        automaticallyImplyLeading: !busy,
        actions: [
          if (!busy)
            IconButton(
              tooltip: 'Đặt lại mặc định',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => setState(() {
                paper = PdfPaper.a4;
                high = widget.store.highQuality(widget.owner);
                compress = true;
              }),
            ),
        ],
      ),
      body: busy
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Panel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle(
                        'Đang tạo PDF…',
                        subtitle:
                            'Vui lòng chờ trong khi ScanPDF xử lý tài liệu.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text(paper.label)),
                          Chip(
                            label: Text(high ? 'Chất lượng cao' : 'Tiêu chuẩn'),
                          ),
                          const Chip(label: Text('PDF dạng ảnh')),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                        value: progress == widget.pages.length
                            ? null
                            : progress / widget.pages.length,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        writing
                            ? 'Đang ghi tệp PDF…'
                            : progress == widget.pages.length
                            ? 'Đang ghép các trang…'
                            : 'Đã xử lý $progress / ${widget.pages.length} trang',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text(cancelling ? 'Đang hủy…' : 'Hủy tạo'),
                        onPressed: cancelling || writing
                            ? null
                            : () => setState(() => cancelling = true),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionTitle(
                    'Thiết lập xuất',
                    subtitle: 'Chọn tên và chất lượng cho tài liệu.',
                  ),
                  const SizedBox(height: 16),
                  Panel(
                    color: mist,
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, color: red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${widget.pages.length} trang  •  ${paper.label}  •  PDF dạng ảnh',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Khổ giấy',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final option in PdfPaper.values)
                        Tooltip(
                          message: option.detail,
                          child: ChoiceChip(
                            label: Text(option.label),
                            selected: paper == option,
                            onSelected: (_) => setState(() => paper = option),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 108,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.pages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => SizedBox(
                        width: 76,
                        child: Panel(
                          padding: const EdgeInsets.all(5),
                          child: Column(
                            children: [
                              Expanded(
                                child: PageThumbnail(page: widget.pages[i]),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Trang ${i + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Tên tài liệu',
                      suffixText: '.pdf',
                    ),
                    validator: (v) => validName(bareName(v ?? ''))
                        ? null
                        : 'Nhập tên tệp hợp lệ',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Chất lượng PDF',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final option in [false, true]) ...[
                    Panel(
                      padding: EdgeInsets.zero,
                      color: high == option ? blush : Colors.white,
                      borderColor: high == option ? red : line,
                      child: ListTile(
                        selected: high == option,
                        leading: Icon(
                          high == option
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: high == option ? red : muted,
                        ),
                        title: Text(option ? 'Chất lượng cao' : 'Tiêu chuẩn'),
                        subtitle: Text(
                          option
                              ? 'Giữ nhiều chi tiết hơn, dung lượng lớn hơn'
                              : 'Dung lượng gọn, thuận tiện khi chia sẻ',
                        ),
                        onTap: () => setState(() => high = option),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Tùy chọn nâng cao',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.compress),
                          title: const Text('Nén ảnh'),
                          subtitle: const Text(
                            'Giảm dung lượng khi đưa ảnh vào PDF',
                          ),
                          value: compress,
                          onChanged: (value) =>
                              setState(() => compress = value),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.text_fields),
                          title: const Text('OCR tiếng Việt · Mẫu'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => previewFeature(
                            context,
                            'OCR tiếng Việt',
                            'Tùy chọn minh họa. Bản hiện tại xuất PDF dạng ảnh.',
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Khóa tệp bằng mật khẩu · Mẫu'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => previewFeature(
                            context,
                            'Khóa tệp',
                            'Tùy chọn minh họa. PDF được xuất ở bản này chưa khóa bằng mật khẩu.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    InfoStrip(
                      icon: Icons.error_outline,
                      text: error!,
                      error: true,
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: busy
          ? null
          : CommandBar(
              child: FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(error == null ? 'Tạo PDF' : 'Thử lại'),
              ),
            ),
    ),
  );
}

class SavedResult extends StatelessWidget {
  const SavedResult({
    super.key,
    required this.store,
    required this.owner,
    required this.doc,
  });
  final ScanStore store;
  final String owner;
  final SavedScan doc;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết quả lưu PDF')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(
          'Tài liệu đã sẵn sàng',
          subtitle: 'Bạn có thể mở hoặc chia sẻ file PDF ngay.',
        ),
        const SizedBox(height: 16),
        const InfoStrip(
          icon: Icons.check_circle_outline,
          text: 'Xuất tệp thành công. Bạn có thể sử dụng PDF ngay.',
        ),
        const SizedBox(height: 12),
        Panel(
          child: Row(
            children: [
              SizedBox(
                width: 54,
                height: 70,
                child: Panel(
                  padding: const EdgeInsets.all(4),
                  color: mist,
                  child: FutureBuilder<Uint8List>(
                    future: store.page(owner, doc, 0),
                    builder: (_, result) => result.hasData
                        ? Image.memory(
                            result.data!,
                            fit: BoxFit.contain,
                            cacheWidth: 150,
                          )
                        : const Icon(Icons.picture_as_pdf_outlined, color: red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.filename,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${doc.count} trang • ${fileSize(doc.size)}',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doc.paper.label} • PDF dạng ảnh',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'TRẠNG THÁI LƯU',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.check_circle_outline, color: green),
                title: Text('Đã lưu trên máy'),
                subtitle: Text('Tệp có thể mở và chia sẻ khi không có mạng.'),
              ),
              const Divider(height: 1),
              if (accountSession(context, owner) case final session?)
                UploadControls(
                  session: session,
                  owner: owner,
                  store: store,
                  doc: doc,
                )
              else
                ListTile(
                  leading: const Icon(Icons.cloud_off_outlined, color: muted),
                  title: const Text('Chưa kết nối lưu trực tuyến'),
                  subtitle: const Text('PDF đang được lưu trên thiết bị này.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => screen<void>(context, const UploadPreview()),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoStrip(
          icon: Icons.lightbulb_outline,
          text:
              'Bạn có thể mở PDF, chuyển trang hoặc chia sẻ mà không cần đợi tải lên.',
        ),
      ],
    ),
    bottomNavigationBar: CommandBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => screen<void>(
              context,
              PdfViewer(store: store, owner: owner, initial: doc),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Mở PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => shareScan(context, store, owner, doc),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Chia sẻ PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Về thư viện'),
          ),
        ],
      ),
    ),
  );
}
