import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'common.dart';
import 'scan_data.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.sample});
  final ScanPage? sample;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  final pages = <ScanPage>[];
  bool ready = false, busy = false, torch = false;
  ScanPage? captured;
  String? error;
  bool opening = false;
  Future<void>? closing;
  bool automatic = true;
  int guide = 0;
  @override
  void initState() {
    super.initState();
    if (widget.sample != null) {
      ready = true;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.sample != null) return;
    if (state != AppLifecycleState.resumed && camera != null) {
      final old = camera!;
      setState(() {
        ready = false;
        camera = null;
        torch = false;
      });
      closing = old.dispose().catchError((Object _) {});
    } else if (state == AppLifecycleState.resumed &&
        camera == null &&
        !ready &&
        error == null) {
      unawaited(start());
    }
  }

  bool get backgrounded => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => true,
    _ => false,
  };

  Future<void> start() async {
    // The permission dialog can send a resume event before initialize returns.
    if (!mounted || opening || camera != null) return;
    opening = true;
    setState(() => error = null);
    CameraController? next;
    var releasedInBackground = false;
    try {
      if (closing case final pending?) {
        await pending;
        closing = null;
      }
      if (!mounted) return;
      final options = await availableCameras();
      if (!mounted || backgrounded) return;
      if (options.isEmpty) throw CameraException('no_camera', '');
      next = CameraController(
        options.firstWhere(
          (o) => o.lensDirection == CameraLensDirection.back,
          orElse: () => options.first,
        ),
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted || backgrounded) {
        releasedInBackground = mounted;
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        ready = true;
      });
    } on CameraException catch (e) {
      await next?.dispose();
      if (!mounted) return;
      setState(
        () => error = switch (e.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' =>
            'Chưa có quyền camera. Bạn có thể cấp quyền trong cài đặt hoặc quay lại để chọn ảnh.',
          'no_camera' => 'Không tìm thấy camera trên thiết bị này.',
          _ => 'Không thể mở camera. Kiểm tra quyền truy cập rồi thử lại.',
        },
      );
    } catch (_) {
      await next?.dispose();
      if (mounted) {
        setState(() => error = 'Không thể mở camera trên thiết bị này.');
      }
    } finally {
      opening = false;
      if (releasedInBackground && mounted && !backgrounded && error == null) {
        unawaited(start());
      }
    }
  }

  Future<void> capture() async {
    final current = camera;
    final sample = widget.sample;
    if ((current == null && sample == null) || !ready || busy) return;
    setState(() => busy = true);
    try {
      final data =
          sample?.bytes ??
          await normalizePhoto(
            await (await current!.takePicture()).readAsBytes(),
          );
      final corners = automatic ? await detectPaper(data) : null;
      if (mounted) {
        setState(
          () => captured = ScanPage(data, corners: corners ?? fullCorners),
        );
      }
    } catch (_) {
      if (mounted) notice(context, 'Không chụp được ảnh. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importPhotos() async {
    if (busy) return;
    if (widget.sample case final sample?) {
      setState(() => pages.add(sample));
      return;
    }
    setState(() => busy = true);
    try {
      final images = await ImagePicker().pickMultiImage(
        maxWidth: 2400,
        maxHeight: 2400,
      );
      final imported = <ScanPage>[];
      var skipped = 0;
      for (final image in images) {
        try {
          imported.add(
            ScanPage(await normalizePhoto(await image.readAsBytes())),
          );
        } catch (_) {
          skipped++;
        }
      }
      if (!mounted) return;
      setState(() => pages.addAll(imported));
      if (skipped > 0) notice(context, 'Không thể mở $skipped ảnh đã chọn.');
    } catch (_) {
      if (mounted) notice(context, 'Không thể mở thư viện ảnh.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> flash() async {
    try {
      await camera!.setFlashMode(torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => torch = !torch);
    } catch (_) {
      if (mounted) notice(context, 'Camera này không hỗ trợ bật đèn');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: scanTheme(dark: true),
    child: Builder(
      builder: (context) => PopScope(
        canPop: pages.isEmpty && captured == null,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (captured != null) {
            setState(() => captured = null);
            return;
          }
          if (await confirm(
                context,
                title: 'Bỏ các ảnh vừa chụp?',
                detail: 'Các ảnh chưa được thêm vào tài liệu.',
                accept: 'Bỏ ảnh',
                cancel: 'Chụp tiếp',
              ) &&
              context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              captured == null
                  ? (widget.sample == null ? 'Máy quét' : 'Máy quét · Mẫu')
                  : 'Xem lại ảnh',
            ),
            actions: [
              if (ready && captured == null && widget.sample == null)
                IconButton(
                  tooltip: torch ? 'Tắt đèn' : 'Bật đèn',
                  onPressed: flash,
                  icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
                ),
            ],
          ),
          body: captured != null
              ? Center(
                  child: Image.memory(captured!.bytes, fit: BoxFit.contain),
                )
              : error != null
              ? StatePanel(
                  icon: Icons.no_photography_outlined,
                  title: 'Camera chưa sẵn sàng',
                  message: error!,
                  action: OutlinedButton(
                    onPressed: start,
                    child: const Text('Thử lại'),
                  ),
                )
              : !ready
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    children: [
                      Text(
                        automatic
                            ? 'Giữ yên máy · Tự căn mép sau khi chụp'
                            : 'Đặt tài liệu trong khung · Căn mép thủ công',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Tự động')),
                          ButtonSegment(value: false, label: Text('Thủ công')),
                        ],
                        selected: {automatic},
                        onSelectionChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => automatic = value.first),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (widget.sample case final sample?)
                                  Image.memory(
                                    sample.bytes,
                                    fit: BoxFit.contain,
                                  )
                                else
                                  CameraPreview(camera!),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: FractionallySizedBox(
                                      widthFactor: .8,
                                      heightFactor: [.82, .50, .87, .72][guide],
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: red,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          children: [
                            for (final (i, label) in [
                              'Tài liệu',
                              'Thẻ',
                              'Hóa đơn',
                              'Sách',
                            ].indexed)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(label),
                                  selected: guide == i,
                                  onSelected: (_) => setState(() => guide = i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          bottomNavigationBar: CommandBar(
            child: captured != null
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => captured = null),
                          child: const Text('Chụp lại'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              pages.add(captured!);
                              captured = null;
                            });
                          },
                          child: const Text('Dùng ảnh này'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Chọn từ thư viện',
                              icon: const Icon(Icons.photo_library_outlined),
                              onPressed: busy ? null : importPhotos,
                            ),
                            Flexible(
                              child: Text(
                                '${pages.length} trang',
                                style: const TextStyle(color: Colors.white70),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(64, 64),
                        ),
                        tooltip: 'Chụp ảnh',
                        onPressed: ready && !busy ? capture : null,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt_outlined, size: 27),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          // Keep the footer at the button's height instead
                          // of filling the entire Scaffold on desktop.
                          heightFactor: 1,
                          child: TextButton(
                            onPressed: pages.isEmpty
                                ? null
                                : () => Navigator.pop(context, pages),
                            child: const Text('Tiếp tục'),
                          ),
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
