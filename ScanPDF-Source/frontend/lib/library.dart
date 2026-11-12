import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'account.dart';
import 'common.dart';
import 'design_preview.dart';
import 'editor.dart';
import 'online/documents.dart';
import 'scan_data.dart';

enum SortScans {
  newest('Mới nhất'),
  oldest('Cũ nhất'),
  name('Tên A–Z');

  const SortScans(this.label);
  final String label;
}

enum DocAction { open, rename, share, delete }

List<PopupMenuEntry<DocAction>> documentMenu({bool includeOpen = true}) => [
  if (includeOpen)
    const PopupMenuItem(
      value: DocAction.open,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.picture_as_pdf_outlined),
        title: Text('Mở PDF'),
      ),
    ),
  const PopupMenuItem(
    value: DocAction.rename,
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.edit_outlined),
      title: Text('Đổi tên'),
    ),
  ),
  const PopupMenuItem(
    value: DocAction.share,
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.share_outlined),
      title: Text('Chia sẻ'),
    ),
  ),
  const PopupMenuDivider(),
  const PopupMenuItem(
    value: DocAction.delete,
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.delete_outline, color: red),
      title: Text('Xóa tài liệu', style: TextStyle(color: red)),
    ),
  ),
];

bool validName(String name) =>
    name.trim().isNotEmpty &&
    name.trim().length <= 100 &&
    !RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) &&
    name.trim() != '.' &&
    name.trim() != '..';
String bareName(String name) => name
    .trim()
    .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
    .trim();

Future<String?> requestName(BuildContext context, String current) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(current));

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.current);
  final String current;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final input = TextEditingController(text: widget.current);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, bareName(input.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đổi tên tài liệu'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: input,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Tên tài liệu',
          suffixText: '.pdf',
        ),
        validator: (v) =>
            validName(bareName(v ?? '')) ? null : 'Tên tài liệu không hợp lệ',
        onFieldSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: submit, child: const Text('Lưu')),
    ],
  );
}

Future<void> shareScan(
  BuildContext context,
  ScanStore store,
  String owner,
  SavedScan doc,
) async {
  final proceed = await showShareSheet(context, doc);
  if (!proceed || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final progress = messenger.showSnackBar(
    const SnackBar(content: Text('Đang chuẩn bị tệp…')),
  );
  try {
    final bytes = await store.pdf(owner, doc);
    progress.close();
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: doc.filename)],
      fileNameOverrides: [doc.filename],
      subject: doc.name,
      sharePositionOrigin: box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  } catch (_) {
    progress.close();
    if (context.mounted) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Không thể chia sẻ tệp PDF'),
          action: SnackBarAction(
            label: 'Thử lại',
            onPressed: () => shareScan(context, store, owner, doc),
          ),
        ),
      );
    }
  }
}

Future<bool> showShareSheet(
  BuildContext context,
  SavedScan doc, {
  bool preview = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionTitle('Chia sẻ tệp'),
              const SizedBox(height: 12),
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: blush,
                    foregroundColor: red,
                    child: Icon(Icons.picture_as_pdf),
                  ),
                  title: Text(doc.filename),
                  subtitle: Text(
                    'PDF • ${fileSize(doc.size)} • ${doc.count} trang',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InfoStrip(
                icon: preview
                    ? Icons.science_outlined
                    : Icons.offline_pin_outlined,
                text: preview
                    ? 'Mẫu bảng chia sẻ. Không có tệp nào được gửi.'
                    : 'Tệp đã lưu trên máy và sẵn sàng chia sẻ.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Chia sẻ qua ứng dụng',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(Icons.forum_outlined, size: 18),
                    label: Text('Zalo'),
                  ),
                  Chip(
                    avatar: Icon(Icons.mail_outline, size: 18),
                    label: Text('Gmail'),
                  ),
                  Chip(
                    avatar: Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text('Messenger'),
                  ),
                  Chip(
                    avatar: Icon(Icons.send_outlined, size: 18),
                    label: Text('Quick Share'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Ví dụ các ứng dụng đích. Thiết bị sẽ hiển thị danh sách ứng dụng thực tế.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (!preview)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheet, true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Mở bảng chia sẻ của thiết bị'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheet, false),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

Future<bool> confirmDelete(BuildContext context, SavedScan doc) => confirm(
  context,
  title: 'Xóa tài liệu?',
  detail:
      '“${doc.filename}” sẽ bị xóa khỏi ScanPDF trên thiết bị. Bản đã chia sẻ qua ứng dụng khác không bị ảnh hưởng.',
  accept: 'Xóa tài liệu',
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.owner,
    required this.onSignOut,
    this.initialTab = 0,
  });
  final ScanStore store;
  final String owner;
  final Future<void> Function() onSignOut;
  final int initialTab;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final search = TextEditingController();
  late int tab = widget.initialTab;
  bool launching = false, busy = false, grid = false, localOnly = false;
  SortScans sort = SortScans.newest;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    if (launching) return;
    setState(() => launching = true);
    try {
      final pages = await choosePages(
        context,
        allowSample: !widget.owner.startsWith('auth:'),
      );
      if (!mounted || pages.isEmpty) return;
      await screen<void>(
        context,
        PagesScreen(store: widget.store, owner: widget.owner, initial: pages),
      );
    } finally {
      if (mounted) setState(() => launching = false);
    }
  }

  Future<void> selectSort() async {
    final value = await showModalBottomSheet<SortScans>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SectionTitle('Sắp xếp tài liệu'),
            ),
            for (final option in SortScans.values)
              ListTile(
                title: Text(option.label),
                trailing: sort == option
                    ? const Icon(Icons.check, color: red)
                    : null,
                selected: sort == option,
                onTap: () => Navigator.pop(ctx, option),
              ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => sort = value);
  }

  Future<void> action(SavedScan doc, DocAction action) async {
    if (busy) return;
    switch (action) {
      case DocAction.open:
        await screen<void>(
          context,
          PdfViewer(store: widget.store, owner: widget.owner, initial: doc),
        );
        if (mounted) setState(() {});
      case DocAction.share:
        await shareScan(context, widget.store, widget.owner, doc);
      case DocAction.rename:
        final name = await requestName(context, doc.name);
        if (!mounted || name == null || name == doc.name) return;
        await change(
          () => widget.store.rename(widget.owner, doc, name),
          'Đã đổi tên tài liệu',
          'Không thể đổi tên tài liệu',
        );
      case DocAction.delete:
        if (!await confirmDelete(context, doc) || !mounted) return;
        await change(
          () => widget.store.delete(widget.owner, doc),
          'Đã xóa tài liệu',
          'Không thể xóa tài liệu',
        );
    }
  }

  Future<void> change(
    Future<Object?> Function() task,
    String done,
    String error,
  ) async {
    setState(() => busy = true);
    try {
      await task();
      if (mounted) notice(context, done);
    } catch (_) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.store.list(widget.owner);
    final query = search.text.trim().toLowerCase();
    final shown =
        docs.where((d) => d.filename.toLowerCase().contains(query)).toList()
          ..sort(
            (a, b) => switch (sort) {
              SortScans.newest => b.created.compareTo(a.created),
              SortScans.oldest => a.created.compareTo(b.created),
              SortScans.name => a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              ),
            },
          );
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [BrandMark(size: 34), SizedBox(width: 10), Text('ScanPDF')],
        ),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: 'Tài khoản',
              onPressed: () => setState(() => tab = 1),
              icon: const CircleAvatar(
                radius: 15,
                backgroundColor: blush,
                foregroundColor: red,
                child: Icon(Icons.person, size: 17),
              ),
            ),
        ],
      ),
      body: tab == 1
          ? AccountView(
              store: widget.store,
              owner: widget.owner,
              onRefresh: () => setState(() {}),
              onSignOut: widget.onSignOut,
            )
          : SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(
                          'Thư viện tài liệu',
                          subtitle:
                              '${docs.length} tài liệu  •  ${fileSize(docs.fold<int>(0, (s, d) => s + d.size))} trên máy',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Tìm tài liệu theo tên…',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Xóa tìm kiếm',
                                    onPressed: () {
                                      search.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                heightFactor: 1,
                                child: TextButton.icon(
                                  onPressed: selectSort,
                                  icon: const Icon(Icons.swap_vert),
                                  label: Text(sort.label),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: grid
                                  ? 'Xem dạng danh sách'
                                  : 'Xem dạng lưới',
                              icon: Icon(
                                grid
                                    ? Icons.view_list_outlined
                                    : Icons.grid_view_outlined,
                              ),
                              onPressed: () => setState(() => grid = !grid),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ChoiceChip(
                                label: Text('Tất cả (${docs.length})'),
                                selected: !localOnly,
                                onSelected: (_) =>
                                    setState(() => localOnly = false),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Đã lưu trên máy'),
                                selected: localOnly,
                                onSelected: (_) =>
                                    setState(() => localOnly = true),
                              ),
                              const SizedBox(width: 6),
                              if (accountSession(context, widget.owner)
                                  case final session?)
                                ActionChip(
                                  label: const Text('Thư viện trực tuyến'),
                                  avatar: const Icon(Icons.cloud_outlined),
                                  onPressed: () => screen<void>(
                                    context,
                                    CloudLibrary(
                                      session: session,
                                      owner: widget.owner,
                                    ),
                                  ),
                                )
                              else
                                ActionChip(
                                  label: const Text('Đang đồng bộ · Mẫu'),
                                  onPressed: () => screen<void>(
                                    context,
                                    const UploadPreview(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? StatePanel(
                            icon: docs.isEmpty
                                ? Icons.folder_open_outlined
                                : Icons.search_off,
                            title: docs.isEmpty
                                ? 'Chưa có tài liệu'
                                : 'Không tìm thấy tài liệu',
                            message: docs.isEmpty
                                ? 'Quét giấy tờ hoặc chọn ảnh để tạo PDF đầu tiên.'
                                : 'Thử tìm bằng tên khác.',
                            action: docs.isEmpty
                                ? OutlinedButton(
                                    onPressed: launching ? null : scan,
                                    child: const Text('Quét tài liệu đầu tiên'),
                                  )
                                : null,
                          )
                        : grid
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 230,
                                  mainAxisExtent: 218,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: shown.length,
                            itemBuilder: (_, i) => GridDocCard(
                              key: ValueKey(shown[i].id),
                              store: widget.store,
                              owner: widget.owner,
                              doc: shown[i],
                              onAction: (a) => action(shown[i], a),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: shown.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => DocCard(
                              key: ValueKey(shown[i].id),
                              store: widget.store,
                              owner: widget.owner,
                              doc: shown[i],
                              onAction: (a) => action(shown[i], a),
                            ),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: tab != 0
          ? null
          : FloatingActionButton.extended(
              backgroundColor: red,
              foregroundColor: Colors.white,
              onPressed: launching ? null : scan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Quét mới'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder, color: red),
            label: 'Thư viện',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: red),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}

class _DocumentThumbnail extends StatefulWidget {
  _DocumentThumbnail({
    required this.store,
    required this.owner,
    required this.doc,
    required this.fit,
    required this.cacheWidth,
    this.iconSize,
  }) : super(key: ValueKey((store, owner, doc.id)));

  final ScanStore store;
  final String owner;
  final SavedScan doc;
  final BoxFit fit;
  final int cacheWidth;
  final double? iconSize;

  @override
  State<_DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends State<_DocumentThumbnail> {
  late final thumbnail = widget.store.page(widget.owner, widget.doc, 0);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: thumbnail,
    builder: (_, snapshot) => snapshot.hasData
        ? Image.memory(
            snapshot.data!,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
          )
        : Icon(
            Icons.picture_as_pdf_outlined,
            color: red,
            size: widget.iconSize,
          ),
  );
}

class GridDocCard extends StatelessWidget {
  const GridDocCard({
    super.key,
    required this.store,
    required this.owner,
    required this.doc,
    required this.onAction,
  });
  final ScanStore store;
  final String owner;
  final SavedScan doc;
  final ValueChanged<DocAction> onAction;
  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onAction(DocAction.open),
            child: SizedBox.expand(
              child: _DocumentThumbnail(
                store: store,
                owner: owner,
                doc: doc,
                fit: BoxFit.contain,
                cacheWidth: 240,
              ),
            ),
          ),
        ),
        const Divider(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${doc.count} trang • ${fileSize(doc.size)}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const Text(
                    'Đã lưu trên máy',
                    style: TextStyle(fontSize: 11, color: green),
                  ),
                ],
              ),
            ),
            PopupMenuButton<DocAction>(
              tooltip: 'Tùy chọn tài liệu',
              itemBuilder: (_) => documentMenu(),
              onSelected: onAction,
            ),
          ],
        ),
      ],
    ),
  );
}

class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.store,
    required this.owner,
    required this.doc,
    required this.onAction,
  });
  final ScanStore store;
  final String owner;
  final SavedScan doc;
  final ValueChanged<DocAction> onAction;
  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatCompactDate(doc.created);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: () => onAction(DocAction.open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 1, 10),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 70,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: mist,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _DocumentThumbnail(
                  store: store,
                  owner: owner,
                  doc: doc,
                  fit: BoxFit.cover,
                  cacheWidth: 140,
                  iconSize: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doc.count} trang  •  ${fileSize(doc.size)}  •  $date',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '✓  Đã lưu trên máy',
                      style: TextStyle(
                        fontSize: 11,
                        color: green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<DocAction>(
                tooltip: 'Tùy chọn tài liệu',
                itemBuilder: (_) => documentMenu(),
                onSelected: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PdfViewer extends StatefulWidget {
  const PdfViewer({
    super.key,
    required this.store,
    required this.owner,
    required this.initial,
  });
  final ScanStore store;
  final String owner;
  final SavedScan initial;
  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  late SavedScan doc = widget.initial;
  final pageController = PageController();
  final transform = TransformationController();
  double zoom = 1;
  late List<Future<Uint8List>> pages = List.generate(
    doc.count,
    (i) => widget.store.page(widget.owner, doc, i),
  );
  int index = 0;
  bool busy = false;

  @override
  void dispose() {
    pageController.dispose();
    transform.dispose();
    super.dispose();
  }

  void setZoom(double value) {
    final scale = value.clamp(1.0, 4.0);
    transform.value = Matrix4.diagonal3Values(scale, scale, 1);
    setState(() => zoom = scale);
  }

  Future<void> details() => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('Chi tiết tệp', subtitle: doc.filename),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Định dạng'),
              subtitle: Text('PDF dạng ảnh • ${doc.paper.label}'),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Số trang và dung lượng'),
              subtitle: Text('${doc.count} trang • ${fileSize(doc.size)}'),
            ),
            const ListTile(
              leading: Icon(Icons.offline_pin_outlined, color: green),
              title: Text('Đã lưu trên máy'),
            ),
          ],
        ),
      ),
    ),
  );

  void viewerTools() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (accountSession(sheet, widget.owner) case final session?)
              UploadControls(
                session: session,
                owner: widget.owner,
                store: widget.store,
                doc: doc,
              ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Nhận dạng văn bản (OCR) · Mẫu'),
              onTap: () {
                Navigator.pop(sheet);
                screen<void>(context, const OcrPreview());
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('In tài liệu · Mẫu'),
              onTap: () {
                Navigator.pop(sheet);
                previewFeature(
                  context,
                  'In tài liệu',
                  'Màn hình minh họa. Bạn có thể chia sẻ PDF tới ứng dụng có hỗ trợ in.',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Chi tiết tệp'),
              onTap: () {
                Navigator.pop(sheet);
                details();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên tệp'),
              onTap: () {
                Navigator.pop(sheet);
                action(DocAction.rename);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_document),
              title: const Text('Chỉnh sửa lại · Mẫu'),
              onTap: () {
                Navigator.pop(sheet);
                previewFeature(
                  context,
                  'Chỉnh sửa lại',
                  'Có thể chỉnh ảnh trong phiên quét trước khi xuất. Chỉnh PDF đã lưu là màn hình minh họa.',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Xuất ảnh trang hiện tại'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(sharePage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: red),
              title: const Text('Xóa tài liệu'),
              onTap: () {
                Navigator.pop(sheet);
                action(DocAction.delete);
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> sharePage() async {
    try {
      final pageIndex = index;
      final bytes = await pages[pageIndex];
      final name = '${doc.name}-trang-${pageIndex + 1}.jpg';
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/jpeg', name: name)],
        fileNameOverrides: [name],
      );
    } catch (_) {
      if (mounted) notice(context, 'Không thể xuất ảnh trang hiện tại.');
    }
  }

  Future<void> pickPage() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SectionTitle(
                  'Chuyển đến trang',
                  subtitle: '${doc.count} trang • ${doc.filename}',
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 135,
                    mainAxisExtent: 152,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: doc.count,
                  itemBuilder: (context, i) => OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: index == i ? blush : Colors.white,
                      side: BorderSide(color: index == i ? red : line),
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, i),
                    child: Column(
                      children: [
                        Expanded(
                          child: FutureBuilder<Uint8List>(
                            future: pages[i],
                            builder: (_, result) {
                              return result.hasData
                                  ? Image.memory(
                                      result.data!,
                                      fit: BoxFit.contain,
                                      cacheWidth: 145,
                                    )
                                  : const Icon(Icons.description_outlined);
                            },
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text('Trang ${i + 1}', maxLines: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && target != null && pageController.hasClients) {
      pageController.jumpToPage(target);
    }
  }

  Future<void> action(DocAction action) async {
    if (busy) return;
    if (action == DocAction.share) {
      return shareScan(context, widget.store, widget.owner, doc);
    }
    try {
      if (action == DocAction.rename) {
        final name = await requestName(context, doc.name);
        if (!mounted || name == null || name == doc.name) return;
        setState(() => busy = true);
        final updated = await widget.store.rename(widget.owner, doc, name);
        if (mounted) {
          setState(() => doc = updated);
          notice(context, 'Đã đổi tên tài liệu');
        }
        return;
      }
      if (action == DocAction.delete) {
        if (!await confirmDelete(context, doc) || !mounted) return;
        setState(() => busy = true);
        await widget.store.delete(widget.owner, doc);
        if (mounted) {
          notice(context, 'Đã xóa tài liệu');
          Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) notice(context, 'Không thể cập nhật tài liệu');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(doc.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Chia sẻ PDF',
          onPressed: busy ? null : () => action(DocAction.share),
          icon: const Icon(Icons.share_outlined),
        ),
        IconButton(
          tooltip: 'Tùy chọn tài liệu',
          icon: const Icon(Icons.more_vert),
          onPressed: busy ? null : viewerTools,
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Container(
          color: mist,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 16, color: green),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Đã lưu trên máy',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Text(
                'PDF  •  ${fileSize(doc.size)}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xffeae8e9),
            child: PageView.builder(
              controller: pageController,
              scrollDirection: Axis.vertical,
              itemCount: doc.count,
              onPageChanged: (i) {
                setState(() => index = i);
                setZoom(1);
              },
              itemBuilder: (context, i) => FutureBuilder<Uint8List>(
                future: pages[i],
                builder: (context, s) {
                  if (s.hasError) {
                    return StatePanel(
                      icon: Icons.broken_image_outlined,
                      title: 'Không thể mở trang PDF',
                      message: 'Tệp xem trước có thể chưa được lưu đầy đủ.',
                      action: OutlinedButton(
                        onPressed: () => setState(
                          () => pages[i] = widget.store.page(
                            widget.owner,
                            doc,
                            i,
                          ),
                        ),
                        child: const Text('Thử lại'),
                      ),
                    );
                  }
                  if (!s.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return InteractiveViewer(
                    transformationController: i == index ? transform : null,
                    onInteractionEnd: (_) {
                      if (i == index) {
                        setState(
                          () => zoom = transform.value.getMaxScaleOnAxis(),
                        );
                      }
                    },
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: doc.paper == PdfPaper.original
                            ? Image.memory(s.data!, fit: BoxFit.contain)
                            : AspectRatio(
                                aspectRatio: doc.paper == PdfPaper.letter
                                    ? 8.5 / 11
                                    : 210 / 297,
                                child: ColoredBox(
                                  color: Colors.white,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Image.memory(
                                      s.data!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Material(
          color: mist,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Thu nhỏ',
                onPressed: zoom <= 1 ? null : () => setZoom(zoom - .25),
                icon: const Icon(Icons.remove),
              ),
              Text('${(zoom * 100).round()}%'),
              IconButton(
                tooltip: 'Phóng to',
                onPressed: zoom >= 4 ? null : () => setZoom(zoom + .25),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Vừa trang',
                onPressed: () => setZoom(1),
                icon: const Icon(Icons.fit_screen),
              ),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: CommandBar(
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              child: TextButton.icon(
                onPressed: busy ? null : pickPage,
                icon: const Icon(Icons.grid_view_outlined, size: 18),
                label: Text('Trang ${index + 1} / ${doc.count}'),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: busy ? null : () => action(DocAction.share),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Chia sẻ PDF'),
          ),
        ],
      ),
    ),
  );
}
