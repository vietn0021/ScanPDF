import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'stitch_gallery.dart';

const showDesignPreview = bool.fromEnvironment('DESIGN_PREVIEW');

class DesignPreview extends StatelessWidget {
  const DesignPreview({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mẫu giao diện')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoStrip(
          icon: Icons.info_outline,
          text:
              'Các trạng thái dưới đây dùng dữ liệu minh họa. Không tác động đến tài liệu hay tài khoản.',
        ),
        const SizedBox(height: 16),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.design_services_outlined),
                title: const Text('Đối chiếu 19 màn hình Stitch'),
                subtitle: const Text('Bản gốc và giao diện Flutter tương ứng'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(context, const StitchGallery()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Xác nhận tài khoản'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(
                  context,
                  Scaffold(
                    appBar: AppBar(title: const Text('Xác nhận tài khoản')),
                    body: const StatePanel(
                      icon: Icons.mail_outline,
                      title: 'Kiểm tra email',
                      message:
                          'Mẫu màn hình chờ người dùng xác nhận địa chỉ email trước khi đăng nhập.',
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Trạng thái lưu trực tuyến'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(context, const UploadPreview()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Nhận dạng văn bản · Giai đoạn 2'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(context, const OcrPreview()),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum _Upload {
  pending('Đang tải lên', Icons.cloud_upload_outlined),
  saved('Đã lưu trực tuyến', Icons.cloud_done_outlined),
  offline('Mất kết nối', Icons.cloud_off_outlined),
  failed('Tải lên thất bại', Icons.error_outline);

  const _Upload(this.label, this.icon);
  final String label;
  final IconData icon;
}

class UploadPreview extends StatefulWidget {
  const UploadPreview({super.key});
  @override
  State<UploadPreview> createState() => _UploadPreviewState();
}

class _UploadPreviewState extends State<UploadPreview> {
  _Upload state = _Upload.offline;
  bool wifiOnly = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết quả lưu PDF')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(
          'Ghi chú môn học.pdf',
          subtitle: '3 trang • Dữ liệu minh họa',
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                'Scan Cloud',
                subtitle: 'Dung lượng minh họa • Không kết nối máy chủ',
              ),
              const SizedBox(height: 10),
              const LinearProgressIndicator(value: .20),
              const SizedBox(height: 6),
              const Text(
                '1 / 5 GB · Dữ liệu mẫu',
                style: TextStyle(color: muted),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tự động sao lưu qua Wi-Fi'),
                value: wifiOnly,
                onChanged: (value) => setState(() => wifiOnly = value),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Đồng bộ ngay · Mẫu'),
                onPressed: () => setState(() => state = _Upload.pending),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final value in _Upload.values)
              ChoiceChip(
                label: Text(value.label),
                selected: state == value,
                onSelected: (_) => setState(() => state = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.check_circle_outline, color: green),
                title: Text('Đã lưu trên máy'),
                subtitle: Text('Vẫn mở và chia sẻ được bản cục bộ.'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  state.icon,
                  color: state == _Upload.saved ? green : red,
                ),
                title: Text(state.label),
                subtitle: Text(switch (state) {
                  _Upload.pending => 'Đang tải bản sao PDF lên kho lưu trữ.',
                  _Upload.saved => 'Bản sao PDF đã có trên kho lưu trữ.',
                  _Upload.offline =>
                    'PDF đã được lưu trên máy. Kết nối mạng để thử lại.',
                  _Upload.failed =>
                    'Không thể tải bản sao PDF lên. Bản trên máy vẫn an toàn.',
                }),
              ),
              if (state == _Upload.pending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: LinearProgressIndicator(value: .65),
                ),
              if (state == _Upload.offline || state == _Upload.failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                    onPressed: () => setState(() => state = _Upload.pending),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum OcrStep {
  scope('Chọn trang'),
  working('Đang xử lý'),
  result('Kết quả'),
  empty('Không có chữ'),
  error('Lỗi');

  const OcrStep(this.label);
  final String label;
}

class OcrPreview extends StatefulWidget {
  const OcrPreview({super.key, this.initial = OcrStep.scope});
  final OcrStep initial;
  @override
  State<OcrPreview> createState() => _OcrPreviewState();
}

class _OcrPreviewState extends State<OcrPreview> {
  late OcrStep state = widget.initial;
  bool all = true;
  int page = 0;
  final samples = const [
    'GHI CHÚ MÔN HỌC\n\n1. Chuẩn bị tài liệu\nĐặt giấy trên mặt phẳng và kiểm tra ánh sáng trước khi chụp.',
    'VÍ DỤ THỰC HÀNH\n\n2. Xử lý hình ảnh\nĐiều chỉnh độ sáng để chữ rõ hơn và kiểm tra bốn góc giấy.',
    'TÓM TẮT BÀI HỌC\n\n3. Lưu tài liệu\nKiểm tra thứ tự trang và xuất PDF trước khi chia sẻ.',
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhận dạng văn bản')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoStrip(
          icon: Icons.info_outline,
          text: 'Mẫu OCR giai đoạn 2 · Dữ liệu minh họa',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: [
            for (final value in OcrStep.values)
              ChoiceChip(
                label: Text(value.label),
                selected: state == value,
                onSelected: (_) => setState(() => state = value),
              ),
          ],
        ),
        const SizedBox(height: 18),
        switch (state) {
          OcrStep.scope => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(
                  'Chọn phạm vi',
                  subtitle: 'Ghi chú môn học.pdf • 3 trang',
                ),
                const SizedBox(height: 12),
                const InfoStrip(
                  icon: Icons.language,
                  text:
                      'Tiếng Việt · Văn bản được trích xuất riêng, PDF gốc không thay đổi.',
                ),
                for (final value in [false, true])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      all == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: red,
                    ),
                    title: Text(value ? 'Tất cả các trang' : 'Trang hiện tại'),
                    subtitle: Text(value ? 'Toàn bộ 3 trang' : 'Trang 1 / 3'),
                    onTap: () => setState(() => all = value),
                  ),
                FilledButton(
                  onPressed: () => setState(() => state = OcrStep.working),
                  child: const Text('Bắt đầu nhận dạng'),
                ),
              ],
            ),
          ),
          OcrStep.working => Panel(
            child: Column(
              children: [
                const SectionTitle('Đang nhận dạng văn bản'),
                const SizedBox(height: 18),
                SizedBox.square(
                  dimension: 86,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: all ? .66 : .5,
                          strokeWidth: 6,
                        ),
                      ),
                      Text(
                        all ? '66%' : '50%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(all ? 'Trang 2 / 3' : 'Trang 1 / 1'),
                const SizedBox(height: 14),
                for (var i = 0; i < (all ? 3 : 1); i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      i == 0 && all
                          ? Icons.check_circle_outline
                          : i == (all ? 1 : 0)
                          ? Icons.sync
                          : Icons.hourglass_empty,
                      color: i == 0 && all ? green : red,
                    ),
                    title: Text('Trang ${i + 1}'),
                    subtitle: Text(
                      i == 0 && all
                          ? 'Đã xử lý'
                          : i == (all ? 1 : 0)
                          ? 'Đang quét'
                          : 'Chờ xử lý',
                    ),
                  ),
                FilledButton(
                  onPressed: () => setState(() => state = OcrStep.result),
                  child: const Text('Xem kết quả mẫu'),
                ),
                TextButton(
                  onPressed: () => setState(() => state = OcrStep.scope),
                  child: const Text('Hủy'),
                ),
              ],
            ),
          ),
          OcrStep.result => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoStrip(
                icon: Icons.info_outline,
                text: 'Kết quả có thể sai dấu. Hãy kiểm tra trước khi sử dụng.',
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < samples.length; i++)
                    ButtonSegment(value: i, label: Text('Trang ${i + 1}')),
                ],
                selected: {page},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => page = s.first),
              ),
              const SizedBox(height: 12),
              Text(
                '${samples[page].split(RegExp(r'\s+')).length} từ • ${samples[page].length} ký tự',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 8),
              Panel(
                child: SelectableText(
                  samples[page],
                  style: const TextStyle(height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Sao chép văn bản'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: samples[page]));
                  if (context.mounted) {
                    notice(context, 'Đã sao chép văn bản mẫu');
                  }
                },
              ),
            ],
          ),
          OcrStep.empty => const StatePanel(
            icon: Icons.text_fields,
            title: 'Không tìm thấy văn bản',
            message: 'Thử dùng ảnh rõ hơn hoặc tăng ánh sáng trước khi quét.',
          ),
          OcrStep.error => StatePanel(
            icon: Icons.error_outline,
            title: 'Không thể nhận dạng văn bản',
            message: 'Hãy thử lại hoặc chọn một trang khác.',
            action: OutlinedButton(
              onPressed: () => setState(() => state = OcrStep.scope),
              child: const Text('Thử lại'),
            ),
          ),
        },
      ],
    ),
  );
}
