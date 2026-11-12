import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'camera_screen.dart';
import 'common.dart';
import 'design_preview.dart';
import 'editor.dart';
import 'library.dart';
import 'main.dart' show StartupScreen;
import 'scan_data.dart';

enum StitchFrame {
  startup('Khởi động và kiểm tra phiên', Icons.shield_outlined),
  login('Đăng nhập và lỗi xác thực', Icons.login),
  signup('Tạo tài khoản', Icons.person_add_outlined),
  account('Hồ sơ và đồng bộ', Icons.account_circle_outlined),
  password('Đổi mật khẩu', Icons.lock_reset),
  library('Thư viện tài liệu', Icons.folder_outlined),
  source('Chọn nguồn và quyền camera', Icons.add_photo_alternate_outlined),
  camera('Máy quét camera', Icons.camera_alt_outlined),
  crop('Cắt viền và nắn góc', Icons.crop),
  filter('Chỉnh ảnh và bộ lọc', Icons.tune),
  pages('Sắp xếp trang', Icons.grid_view),
  export('Thiết lập xuất PDF', Icons.picture_as_pdf_outlined),
  progress('Đang tạo PDF và lỗi', Icons.hourglass_top),
  saved('Kết quả lưu và đồng bộ', Icons.cloud_done_outlined),
  viewer('Trình xem PDF', Icons.menu_book_outlined),
  share('Bảng chia sẻ', Icons.share_outlined),
  ocrScope('OCR: Chọn phạm vi', Icons.document_scanner_outlined),
  ocrProgress('OCR: Tiến trình', Icons.sync),
  ocrResult('OCR: Kết quả', Icons.text_snippet_outlined);

  const StitchFrame(this.title, this.icon);
  final String title;
  final IconData icon;
  String get asset =>
      'assets/stitch/${(index + 1).toString().padLeft(2, '0')}.png';
}

class StitchGallery extends StatelessWidget {
  const StitchGallery({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('19 màn hình Stitch')),
    body: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: StitchFrame.values.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == 0) {
          return const InfoStrip(
            icon: Icons.science_outlined,
            text:
                'Chọn một khung để xem bản gốc và mở giao diện Flutter tương ứng. Dữ liệu minh họa không được lưu vào thư viện của bạn.',
          );
        }
        final frame = StitchFrame.values[index - 1];
        return Panel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: blush,
              foregroundColor: red,
              child: Icon(frame.icon),
            ),
            title: Text(frame.title),
            subtitle: Text('Khung ${frame.index + 1} / 19'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => screen<void>(context, _FrameDetails(frame: frame)),
          ),
        );
      },
    ),
  );
}

class _FrameDetails extends StatefulWidget {
  const _FrameDetails({required this.frame});
  final StitchFrame frame;
  @override
  State<_FrameDetails> createState() => _FrameDetailsState();
}

class _FrameDetailsState extends State<_FrameDetails> {
  Future<({ScanStore store, List<ScanPage> pages, SavedScan document})>? data;
  bool opening = false;

  Future<({ScanStore store, List<ScanPage> pages, SavedScan document})>
  prepare() async {
    final store = ScanStore(
      await SharedPreferences.getInstance(),
      inMemory: true,
    );
    final pages = await samplePages();
    await store.updateProfile(
      demoOwner,
      'Nguyễn Văn A · Mẫu',
      null,
      phone: '090 000 0000',
      company: 'ScanPDF Lab',
    );
    final images = pages.map((page) => page.bytes).toList();
    final invoice = [images.last];
    await store.save(
      demoOwner,
      'Hóa đơn tháng 10 · Mẫu',
      invoice,
      await makePdf(invoice),
    );
    final document = await store.save(
      demoOwner,
      'Ghi chú môn học',
      images,
      await makePdf(images),
    );
    return (store: store, pages: pages, document: document);
  }

  Future<void> launch() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final frame = widget.frame;
      Future<void> sampleAuth(
        String email, {
        required bool remember,
        String? name,
      }) async {
        if (mounted) {
          await previewFeature(
            context,
            'Tài khoản mẫu',
            'Đã kiểm tra biểu mẫu. Không có tài khoản thật được tạo.',
          );
        }
      }

      final Widget? quick = switch (frame) {
        StitchFrame.startup => const StartupScreen(preview: true),
        StitchFrame.login => AuthScreen(
          onSignIn: sampleAuth,
          sampleError: true,
        ),
        StitchFrame.signup => AuthScreen(
          onSignIn: sampleAuth,
          initialSignUp: true,
        ),
        StitchFrame.password => const PasswordScreen(),
        StitchFrame.source => const _SourcePreview(),
        StitchFrame.progress => const _ExportProgressPreview(),
        StitchFrame.ocrScope => const OcrPreview(),
        StitchFrame.ocrProgress => const OcrPreview(initial: OcrStep.working),
        StitchFrame.ocrResult => const OcrPreview(initial: OcrStep.result),
        _ => null,
      };
      if (quick != null) {
        await screen<void>(context, quick);
        return;
      }
      final sample = await (data ??= prepare());
      if (!mounted) return;
      if (frame == StitchFrame.share) {
        await showShareSheet(context, sample.document, preview: true);
        return;
      }
      final store = sample.store, pages = sample.pages, doc = sample.document;
      final Widget page = switch (frame) {
        StitchFrame.account || StitchFrame.library => HomeScreen(
          store: store,
          owner: demoOwner,
          initialTab: frame == StitchFrame.account ? 1 : 0,
          onSignOut: () async {
            if (mounted) Navigator.pop(context);
          },
        ),
        StitchFrame.camera => CameraScreen(sample: pages.first),
        StitchFrame.crop => CropScreen(
          page: pages.first,
          index: 0,
          count: pages.length,
        ),
        StitchFrame.filter => FilterScreen(
          page: pages.first,
          index: 0,
          count: pages.length,
          onBatch: (_) {},
        ),
        StitchFrame.pages => PagesScreen(
          store: store,
          owner: demoOwner,
          initial: pages,
        ),
        StitchFrame.export => ExportScreen(
          store: store,
          owner: demoOwner,
          pages: pages,
        ),
        StitchFrame.saved => SavedResult(
          store: store,
          owner: demoOwner,
          doc: doc,
        ),
        StitchFrame.viewer => PdfViewer(
          store: store,
          owner: demoOwner,
          initial: doc,
        ),
        _ => const SizedBox.shrink(),
      };
      await screen<dynamic>(context, page);
    } catch (_) {
      data = null;
      if (mounted) {
        notice(context, 'Không thể mở giao diện mẫu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.frame.title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoStrip(
          icon: Icons.design_services_outlined,
          text:
              'Ảnh đối chiếu gốc từ bộ Stitch. Nút bên dưới mở màn hình Flutter.',
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(widget.frame.asset, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: CommandBar(
      child: FilledButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: Text(opening ? 'Đang chuẩn bị…' : 'Mở giao diện Flutter'),
        onPressed: opening ? null : launch,
      ),
    ),
  );
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thêm tài liệu mới')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoStrip(
          icon: Icons.science_outlined,
          text: 'Mẫu quyền camera. Không yêu cầu quyền của thiết bị.',
        ),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: red),
                title: const Text('Chụp bằng camera'),
                subtitle: const Text('Tự phát hiện mép giấy và nắn góc'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    icon: const Icon(Icons.photo_camera_outlined, color: red),
                    title: const Text('Cho phép ScanPDF sử dụng camera?'),
                    content: const Text(
                      'Giao diện minh họa để xem cách cấp quyền quét tài liệu.',
                    ),
                    actions: [
                      for (final label in [
                        'Khi dùng ứng dụng',
                        'Chỉ lần này',
                        'Không cho phép',
                      ])
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: Text(label),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: red),
                title: const Text('Chọn từ thư viện ảnh'),
                subtitle: const Text('Hỗ trợ nhiều ảnh'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => previewFeature(
                  context,
                  'Thư viện ảnh',
                  'Bản mẫu không đọc ảnh trên thiết bị.',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExportProgressPreview extends StatefulWidget {
  const _ExportProgressPreview();
  @override
  State<_ExportProgressPreview> createState() => _ExportProgressPreviewState();
}

class _ExportProgressPreviewState extends State<_ExportProgressPreview> {
  bool error = false, cancelled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ghi chú môn học.pdf')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoStrip(
          icon: Icons.science_outlined,
          text: 'Dữ liệu minh họa. Không có tệp nào được ghi.',
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                error
                    ? 'Không đủ dung lượng để lưu PDF'
                    : cancelled
                    ? 'Đã hủy tạo PDF'
                    : 'Đang tạo tệp PDF…',
                subtitle: error
                    ? 'Quay lại chỉnh sửa hoặc thử xuất lại.'
                    : '3 trang • Chất lượng cao',
              ),
              if (!error && !cancelled) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(value: .78),
                const SizedBox(height: 8),
                const Text('Đang xử lý trang 3 / 3 · 78%'),
              ],
              const SizedBox(height: 12),
              if (error || cancelled)
                FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('Thử lại'),
                  onPressed: () => setState(() {
                    error = false;
                    cancelled = false;
                  }),
                )
              else
                OutlinedButton(
                  onPressed: () => setState(() => cancelled = true),
                  child: const Text('Hủy tạo'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() {
            error = true;
            cancelled = false;
          }),
          child: const Text('Xem trạng thái lỗi'),
        ),
      ],
    ),
  );
}
