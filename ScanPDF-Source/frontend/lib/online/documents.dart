import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../scan_data.dart';
import 'api_client.dart';
import 'session_store.dart';

OnlineSession? accountSession(BuildContext context, String owner) {
  final session = OnlineScope.of(context);
  return session?.owner == owner ? session : null;
}

String _failure(Object error) => error is ApiFailure
    ? error.message
    : 'Không thể xử lý tệp. Vui lòng thử lại.';

class UploadControls extends StatefulWidget {
  const UploadControls({
    super.key,
    required this.session,
    required this.owner,
    required this.store,
    required this.doc,
  });
  final OnlineSession session;
  final String owner;
  final ScanStore store;
  final SavedScan doc;

  @override
  State<UploadControls> createState() => _UploadControlsState();
}

class _UploadControlsState extends State<UploadControls> {
  static const _tooLarge = ApiFailure(
    0,
    'PDF lớn hơn 20 MiB nên chưa thể lưu trực tuyến. Hãy xuất lại ở chất lượng tiêu chuẩn hoặc ít trang hơn.',
  );
  String get key => 'scanpdf.upload.${widget.owner}.${widget.doc.id}';
  late bool ready = widget.store.prefs.getBool('$key.ready') ?? false;
  bool busy = false;
  String? error;

  Future<void> upload() async {
    final session = widget.session;
    if (session.owner != widget.owner || busy || ready) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.doc.size > ScanApi.maxPdf) throw _tooLarge;
      final prefs = widget.store.prefs;
      final bytes = await widget.store.pdf(widget.owner, widget.doc);
      if (bytes.length > ScanApi.maxPdf) throw _tooLarge;
      final previous = prefs.getStringList(key);
      final ticket = previous ?? [const Uuid().v4(), widget.doc.filename];
      if (previous == null && !await prefs.setStringList(key, ticket)) {
        throw const FileSystemException('Không thể lưu mã tải lên');
      }
      if (session.owner != widget.owner) {
        throw const ApiFailure(401, 'Hãy đăng nhập lại.');
      }
      final saved = await session.authorized(
        (token) => session.api.upload(token, ticket[0], ticket[1], bytes),
      );
      if (!await prefs.setString('$key.cloudId', saved['id'] as String) ||
          !await prefs.setBool('$key.ready', true)) {
        throw const FileSystemException('Không thể lưu trạng thái tải lên');
      }
      if (mounted) setState(() => ready = true);
    } catch (failure) {
      if (mounted) setState(() => error = _failure(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      ready ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
      color: ready ? green : red,
    ),
    title: Text(
      ready
          ? 'Đã lưu trực tuyến'
          : busy
          ? 'Đang tải lên…'
          : error != null
          ? 'Thử tải lại'
          : 'Lưu trực tuyến',
    ),
    subtitle: Text(
      error ??
          (ready
              ? 'Tệp có trong Thư viện trực tuyến.'
              : 'Lưu một bản PDF riêng tư vào tài khoản của bạn.'),
    ),
    trailing: busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : ready
        ? null
        : const Icon(Icons.chevron_right),
    onTap: ready || busy ? null : upload,
  );
}

class CloudLibrary extends StatefulWidget {
  const CloudLibrary({super.key, required this.session, required this.owner});
  final OnlineSession session;
  final String owner;

  @override
  State<CloudLibrary> createState() => _CloudLibraryState();
}

class _CloudLibraryState extends State<CloudLibrary> {
  final items = <Map<String, dynamic>>[];
  String? cursor, error, opening, deleting;
  bool busy = false;
  OnlineSession get session => widget.session;
  bool get active => mounted && session.owner == widget.owner;

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy || deleting != null || !active) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await session.authorized(
        (token) => session.api.json(
          'GET',
          'documents',
          token: token,
          query: reset || cursor == null ? null : {'cursor': cursor!},
        ),
      );
      if (!active) return;
      final page = (data['items'] as List).cast<Map<String, dynamic>>();
      final next = data['next_cursor'] as String?;
      setState(() {
        if (reset) items.clear();
        items.addAll(page);
        cursor = next;
      });
    } catch (failure) {
      if (active) setState(() => error = _failure(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Map<String, dynamic> item) async {
    if (busy || opening != null || deleting != null || !active) return;
    final id = item['id'] as String;
    if (!await confirm(
          context,
          title: 'Xóa PDF trực tuyến?',
          detail: 'Xóa ${item['filename']} khỏi thư viện trực tuyến.',
          accept: 'Xóa',
        ) ||
        !active ||
        busy ||
        opening != null ||
        deleting != null) {
      return;
    }
    setState(() => deleting = id);
    try {
      await session.authorized(
        (token) => session.api.json('DELETE', 'documents/$id', token: token),
      );
      if (active) setState(() => items.removeWhere((item) => item['id'] == id));
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'scanpdf.upload.${widget.owner}.';
      const suffix = '.cloudId';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix) &&
            key.endsWith(suffix) &&
            prefs.getString(key) == id) {
          final uploadKey = key.substring(0, key.length - suffix.length);
          if (!await prefs.remove('$uploadKey.ready') ||
              !await prefs.remove(uploadKey) ||
              !await prefs.remove(key)) {
            throw const FileSystemException('Không thể dọn trạng thái tải lên');
          }
        }
      }
    } catch (failure) {
      if (mounted && session.owner == widget.owner) {
        notice(context, _failure(failure));
      }
    } finally {
      if (mounted) setState(() => deleting = null);
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    if (opening != null || !active) return;
    final id = item['id'] as String;
    setState(() => opening = id);
    File? downloaded;
    try {
      final user = session.userId!;
      final uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
      if (!uuid.hasMatch(id) || !uuid.hasMatch(user)) {
        throw const FormatException();
      }
      final bytes = await session.authorized(
        (token) => session.api.download(token, id),
      );
      if (bytes.length != item['byte_size'] ||
          sha256.convert(bytes).toString() != item['sha256']) {
        throw const ApiFailure(
          0,
          'Tệp tải về chưa toàn vẹn. Vui lòng thử lại.',
        );
      }
      if (!active) return;
      final cache = await getTemporaryDirectory();
      final directory = await Directory(
        '${cache.path}/scanpdf-cloud/$user',
      ).create(recursive: true);
      // The viewer gets the path only after the verified file has been fully written.
      downloaded = File('${directory.path}/$id-${const Uuid().v4()}.pdf');
      await downloaded.writeAsBytes(bytes, flush: true);
      if (mounted && session.owner == widget.owner) {
        await screen<void>(
          context,
          DownloadedPdfView(
            path: downloaded.path,
            filename: item['filename'] as String,
            pages: item['page_count'] as int,
          ),
        );
      }
    } catch (failure) {
      if (mounted && session.owner == widget.owner) {
        notice(context, _failure(failure));
      }
    } finally {
      try {
        if (downloaded != null && await downloaded.exists()) {
          await downloaded.delete();
        }
      } on FileSystemException {
        // Android can evict any leftover private cache entry.
      }
      if (mounted) setState(() => opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thư viện trực tuyến'),
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: busy ? null : () => load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(
            'PDF của tôi',
            subtitle: 'Chạm vào tài liệu để tải và mở PDF.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            ListTile(
              title: Text(error!),
              trailing: TextButton(
                onPressed: () => load(reset: true),
                child: const Text('Thử lại'),
              ),
            ),
          if (!busy && error == null && items.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_outlined),
              title: Text('Chưa có PDF trực tuyến'),
            ),
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: red),
              title: Text(item['filename'] as String),
              subtitle: Text(
                '${item['page_count']} trang • ${fileSize(item['byte_size'] as int)}',
              ),
              trailing: opening == item['id'] || deleting == item['id']
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Xóa PDF trực tuyến',
                      onPressed: busy || deleting != null || opening != null
                          ? null
                          : () => remove(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
              onTap: opening == null && deleting == null
                  ? () => open(item)
                  : null,
            ),
          if (cursor != null)
            TextButton(
              onPressed: busy ? null : load,
              child: const Text('Xem thêm'),
            ),
        ],
      ),
    ),
  );
}

class DownloadedPdfView extends StatefulWidget {
  const DownloadedPdfView({
    super.key,
    required this.path,
    required this.filename,
    required this.pages,
  });
  final String path, filename;
  final int pages;

  @override
  State<DownloadedPdfView> createState() => _DownloadedPdfViewState();
}

class _DownloadedPdfViewState extends State<DownloadedPdfView> {
  static const channel = MethodChannel('vn.scanpdf/pdf');
  int page = 0;
  late Future<Uint8List?> image = render();

  Future<Uint8List?> render() => channel.invokeMethod<Uint8List>('render', {
    'path': widget.path,
    'page': page,
  });

  void go(int target) => setState(() {
    page = target;
    image = render();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.filename)),
    body: Center(
      child: FutureBuilder<Uint8List?>(
        future: image,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          final bytes = snapshot.data;
          if (bytes == null) return const Text('Không thể mở trang PDF.');
          return InteractiveViewer(
            key: ValueKey(page),
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          );
        },
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Trang trước',
            onPressed: page > 0 ? () => go(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page + 1} / ${widget.pages}'),
          IconButton(
            tooltip: 'Trang sau',
            onPressed: page + 1 < widget.pages ? () => go(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );
}
