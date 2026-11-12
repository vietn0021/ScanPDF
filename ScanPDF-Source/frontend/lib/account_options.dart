import 'package:flutter/material.dart';

import 'common.dart';
import 'design_preview.dart';
import 'scan_data.dart';

class AccountStorage extends StatelessWidget {
  const AccountStorage({super.key, required this.documents, this.openCloud});
  final List<SavedScan> documents;
  final VoidCallback? openCloud;

  @override
  Widget build(BuildContext context) {
    final total = documents.fold<int>(0, (sum, doc) => sum + doc.size);
    final pages = documents.fold<int>(0, (sum, doc) => sum + doc.count);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: blush,
                foregroundColor: red,
                child: Icon(Icons.folder_copy_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dung lượng PDF trên máy',
                      style: TextStyle(color: muted),
                    ),
                    Text(
                      fileSize(total),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.picture_as_pdf_outlined,
                  value: '${documents.length}',
                  label: 'Tài liệu',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  icon: Icons.layers_outlined,
                  value: '$pages',
                  label: 'Tổng số trang',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoStrip(
            icon: openCloud == null
                ? Icons.cloud_off_outlined
                : Icons.cloud_outlined,
            text: openCloud == null
                ? 'PDF vẫn có thể mở và chia sẻ từ thiết bị.'
                : 'Mở thư viện trực tuyến để xem các bản PDF đã tải lên.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline),
            label: const Text('Chi tiết lưu trữ'),
            onPressed: () =>
                screen<void>(context, _StorageDetails(documents: documents)),
          ),
          const Divider(height: 24),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_outlined, color: red),
            title: Text('Google Drive & Scan Cloud'),
            subtitle: Text('Chưa kết nối · Giao diện mẫu'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tự động sao lưu qua Wi-Fi'),
            subtitle: const Text('Thiết lập minh họa'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => screen<void>(context, const UploadPreview()),
          ),
          if (openCloud == null)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.sync),
              label: const Text('Đồng bộ ngay · Mẫu'),
              onPressed: () => screen<void>(context, const UploadPreview()),
            )
          else
            FilledButton.tonalIcon(
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Thư viện trực tuyến'),
              onPressed: openCloud,
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value, label;
  @override
  Widget build(BuildContext context) => Panel(
    color: mist,
    padding: const EdgeInsets.all(10),
    child: Row(
      children: [
        Icon(icon, size: 19, color: red),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StorageDetails extends StatelessWidget {
  const _StorageDetails({required this.documents});
  final List<SavedScan> documents;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết lưu trữ')),
    body: documents.isEmpty
        ? const StatePanel(
            icon: Icons.folder_open_outlined,
            title: 'Chưa có tài liệu',
            message:
                'PDF đã lưu sẽ xuất hiện tại đây cùng dung lượng từng tệp.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const InfoStrip(
                  icon: Icons.info_outline,
                  text:
                      'Dung lượng dưới đây chỉ tính các tệp PDF, chưa gồm ảnh xem trước.',
                );
              }
              final doc = documents[index - 1];
              return Panel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: red,
                  ),
                  title: Text(doc.filename),
                  subtitle: Text('${doc.count} trang'),
                  trailing: Text(fileSize(doc.size)),
                ),
              );
            },
          ),
  );
}

class ScanDefaultsScreen extends StatefulWidget {
  const ScanDefaultsScreen({
    super.key,
    required this.store,
    required this.owner,
  });
  final ScanStore store;
  final String owner;
  @override
  State<ScanDefaultsScreen> createState() => _ScanDefaultsScreenState();
}

class _ScanDefaultsScreenState extends State<ScanDefaultsScreen> {
  late final initial = widget.store.highQuality(widget.owner);
  late bool high = initial;
  bool busy = false;

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.store.setHighQuality(widget.owner, high);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      notice(context, 'Không thể lưu cài đặt. Vui lòng thử lại.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chất lượng quét mặc định')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(
          'Thiết lập PDF',
          subtitle: 'Áp dụng cho tài liệu mới. Có thể đổi khi xuất từng file.',
        ),
        const SizedBox(height: 16),
        const Panel(
          child: Row(
            children: [
              Icon(Icons.description_outlined, color: red),
              SizedBox(width: 12),
              Expanded(child: Text('Khổ A4 • PDF dạng ảnh')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final option in [false, true]) ...[
          Panel(
            color: high == option ? blush : Colors.white,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                high == option
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: high == option ? red : muted,
              ),
              title: Text(option ? 'Chất lượng cao' : 'Tiêu chuẩn'),
              subtitle: Text(
                option ? 'Ưu tiên độ rõ của ảnh' : 'Ưu tiên dung lượng gọn',
              ),
              onTap: busy ? null : () => setState(() => high = option),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    ),
    bottomNavigationBar: CommandBar(
      child: FilledButton(
        onPressed: busy || high == initial ? null : save,
        child: Text(busy ? 'Đang lưu…' : 'Lưu cài đặt'),
      ),
    ),
  );
}

enum AccountInfo { help, privacy, updates }

class AccountInfoScreen extends StatelessWidget {
  const AccountInfoScreen({super.key, required this.type});
  final AccountInfo type;
  @override
  Widget build(BuildContext context) {
    final (title, entries) = switch (type) {
      AccountInfo.help => (
        'Trợ giúp',
        const [
          (
            'Quét tài liệu như thế nào?',
            'Vào Thư viện → Quét mới, rồi chụp hoặc chọn ảnh. Bạn có thể cắt viền, chỉnh ảnh và đổi thứ tự trước khi xuất PDF.',
          ),
          (
            'Không mở được camera?',
            'Kiểm tra quyền camera của ứng dụng hoặc trình duyệt. Bạn cũng có thể chọn ảnh có sẵn để tiếp tục.',
          ),
          (
            'Chia sẻ PDF như thế nào?',
            'Mở tài liệu và bấm Chia sẻ PDF. Android sẽ hiển thị các ứng dụng có thể nhận tệp.',
          ),
        ],
      ),
      AccountInfo.privacy => (
        'Quyền riêng tư',
        const [
          (
            'PDF lưu ở đâu?',
            'Bản thử lưu PDF và ảnh xem trước trong vùng lưu trữ của ứng dụng. ScanPDF chưa kết nối dịch vụ lưu trữ trực tuyến.',
          ),
          (
            'Tài khoản mẫu bảo vệ tài liệu không?',
            'Phiên dùng thử chỉ để trải nghiệm giao diện. Đây chưa phải hệ thống xác thực thật; chỉ dùng dữ liệu mẫu.',
          ),
          (
            'Điều gì xảy ra khi chia sẻ?',
            'Ứng dụng bạn chọn có thể nhận bản sao PDF. Xóa tệp trong ScanPDF không xóa bản sao đã chia sẻ.',
          ),
        ],
      ),
      AccountInfo.updates => (
        'Thông báo',
        const [
          ('Lưu tài liệu', 'Bản hiện tại chỉ lưu PDF trên thiết bị.'),
          (
            'Đồng bộ và OCR',
            'Hai tính năng này chưa kết nối với dữ liệu thật. Có thể xem các màn hình mẫu trong mục Tài khoản.',
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (heading, detail) in entries) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: const TextStyle(color: muted, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
