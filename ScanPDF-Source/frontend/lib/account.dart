import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'common.dart';
import 'account_options.dart';
import 'design_preview.dart';
import 'online/api_client.dart';
import 'online/documents.dart';
import 'online/session_store.dart';
import 'scan_data.dart';

const demoOwner = 'demo@scanpdf.local';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onSignIn,
    this.initialSignUp = false,
    this.sampleError = false,
    this.online,
    this.onOnlineLogin,
  });
  final Future<void> Function(
    String email, {
    required bool remember,
    String? name,
  })
  onSignIn;
  final bool initialSignUp, sampleError;
  final OnlineSession? online;
  final VoidCallback? onOnlineLogin;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController(),
      name = TextEditingController();
  late bool create = widget.initialSignUp;
  bool show = false, busy = false, remember = true, readGuide = false;
  late String? error = widget.sampleError
      ? 'Mẫu lỗi xác thực: thông tin đăng nhập không hợp lệ.'
      : null;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    repeat.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> login({bool demo = false}) async {
    if (busy || (!demo && !form.currentState!.validate())) return;
    if (create && !demo && !readGuide) {
      setState(
        () => error = widget.online == null
            ? 'Đánh dấu đã đọc hướng dẫn trước khi đăng ký.'
            : 'Đánh dấu xác nhận bạn sẽ kiểm tra email sau khi đăng ký.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!demo && widget.online != null) {
        final address = email.text.trim().toLowerCase();
        if (create) {
          await widget.online!.register(address, password.text);
          if (!mounted) return;
          password.clear();
          repeat.clear();
          setState(() => create = false);
          notice(
            context,
            'Kiểm tra email để xác nhận tài khoản trước khi đăng nhập.',
          );
        } else {
          await widget.online!.login(
            address,
            password.text,
            remember: remember,
          );
          widget.onOnlineLogin?.call();
        }
        return;
      }
      await widget.onSignIn(
        demo ? demoOwner : email.text.trim().toLowerCase(),
        remember: demo || remember,
        name: create && !demo ? name.text.trim() : null,
      );
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không thể xử lý yêu cầu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: create
          ? IconButton(
              tooltip: 'Quay lại',
              icon: const Icon(Icons.arrow_back),
              onPressed: busy ? null : () => setState(() => create = false),
            )
          : null,
      title: Text(
        create
            ? (widget.online == null ? 'Tạo tài khoản mẫu' : 'Tạo tài khoản')
            : 'Đăng nhập',
      ),
      actions: [
        IconButton(
          tooltip: 'Trợ giúp',
          icon: const Icon(Icons.help_outline),
          onPressed: () => screen<void>(
            context,
            const AccountInfoScreen(type: AccountInfo.help),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      BrandMark(),
                      SizedBox(width: 10),
                      Text(
                        'ScanPDF',
                        style: TextStyle(
                          color: red,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SectionTitle(
                    create ? 'Bắt đầu với ScanPDF' : 'Chào mừng trở lại',
                    subtitle:
                        'Quét giấy tờ, sắp xếp và chia sẻ PDF ngay trên điện thoại.',
                  ),
                  const SizedBox(height: 18),
                  InfoStrip(
                    icon: Icons.info_outline,
                    text: widget.online == null
                        ? 'Chế độ dùng thử lưu dữ liệu trên thiết bị.'
                        : 'Dùng email để đăng nhập và lưu PDF riêng tư vào tài khoản.',
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    InfoStrip(
                      icon: Icons.error_outline,
                      text: error!,
                      error: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (create && widget.online == null) ...[
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Nhập họ và tên'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'demo@example.com',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Nhập địa chỉ email hợp lệ',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    onChanged: (_) {
                      if (create) setState(() {});
                    },
                    enabled: !busy,
                    obscureText: !show,
                    decoration: InputDecoration(
                      labelText: widget.online == null
                          ? 'Mật khẩu mẫu'
                          : 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                        onPressed: () => setState(() => show = !show),
                        icon: Icon(
                          show
                              ? Icons.visibility_off
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => create
                        ? (passwordChecks(v ?? '').every((check) => check)
                              ? null
                              : 'Mật khẩu chưa đủ yêu cầu')
                        : ((v?.length ?? 0) >= 6
                              ? null
                              : 'Nhập tối thiểu 6 ký tự'),
                  ),
                  if (create) ...[
                    const SizedBox(height: 12),
                    PasswordRules(password.text),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: repeat,
                      enabled: !busy,
                      obscureText: !show,
                      decoration: InputDecoration(
                        labelText: widget.online == null
                            ? 'Xác nhận mật khẩu mẫu'
                            : 'Xác nhận mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: (v) =>
                          v == password.text ? null : 'Mật khẩu không khớp',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.online == null
                            ? 'Tôi đã đọc hướng dẫn bản dùng thử'
                            : 'Tôi sẽ xác nhận địa chỉ email sau khi đăng ký',
                      ),
                      value: readGuide,
                      onChanged: busy
                          ? null
                          : (value) =>
                                setState(() => readGuide = value ?? false),
                    ),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => previewFeature(
                          context,
                          'Quên mật khẩu?',
                          'Đặt lại mật khẩu qua email là phần giao diện mẫu. Chưa có dịch vụ gửi email.',
                        ),
                        child: const Text('Quên mật khẩu?'),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.online == null
                            ? 'Ghi nhớ phiên mẫu trên thiết bị này'
                            : 'Ghi nhớ đăng nhập trên thiết bị này',
                      ),
                      value: remember,
                      onChanged: busy
                          ? null
                          : (value) =>
                                setState(() => remember = value ?? false),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: busy ? null : () => login(),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: Text(
                      create
                          ? (widget.online == null
                                ? 'Tạo hồ sơ mẫu'
                                : 'Đăng ký')
                          : (widget.online == null
                                ? 'Đăng nhập dùng thử'
                                : 'Đăng nhập'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy ? null : () => login(demo: true),
                    child: const Text('Dùng tài khoản mẫu'),
                  ),
                  const SizedBox(height: 8),
                  Panel(
                    color: mist,
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.wifi_off, color: red),
                      title: const Text('Tiếp tục dùng ngoại tuyến'),
                      subtitle: const Text(
                        'Quét và xuất PDF bằng tài khoản mẫu',
                      ),
                      onTap: busy ? null : () => login(demo: true),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final provider in ['Google', 'Zalo']) ...[
                        if (provider == 'Zalo') const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => previewFeature(
                                    context,
                                    'Đăng nhập qua $provider',
                                    'Đây là nút minh họa. Dịch vụ đăng nhập chưa được kết nối.',
                                  ),
                            child: Text('$provider · Mẫu'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            create = !create;
                            error = null;
                          }),
                    child: Text(
                      create
                          ? 'Quay lại đăng nhập'
                          : widget.online == null
                          ? 'Tạo tài khoản mẫu'
                          : 'Tạo tài khoản',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AccountView extends StatelessWidget {
  const AccountView({
    super.key,
    required this.store,
    required this.owner,
    required this.onRefresh,
    required this.onSignOut,
  });
  final ScanStore store;
  final String owner;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) {
    final avatar = store.avatar(owner);
    final session = accountSession(context, owner);
    final email = session?.email;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(
                'Tài khoản',
                subtitle: 'Trạng thái tài khoản',
              ),
            ),
            IconButton(
              tooltip: 'Thông báo',
              icon: const Icon(Icons.notifications_none),
              onPressed: () => screen<void>(
                context,
                const AccountInfoScreen(type: AccountInfo.updates),
              ),
            ),
            IconButton(
              tooltip: 'Trợ giúp',
              icon: const Icon(Icons.help_outline),
              onPressed: () => screen<void>(
                context,
                const AccountInfoScreen(type: AccountInfo.help),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: blush,
                foregroundColor: red,
                foregroundImage: avatar == null
                    ? null
                    : MemoryImage(base64Decode(avatar)),
                child: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name(owner, email: email),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      email ?? owner,
                      style: const TextStyle(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: blush,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        email == null ? 'Hồ sơ dùng thử' : 'Tài khoản ScanPDF',
                        style: const TextStyle(color: red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          color: blush,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: Icon(Icons.workspace_premium_outlined),
            ),
            title: const Text('Mở khóa ScanPDF Pro'),
            subtitle: const Text('OCR và lưu trữ mở rộng · Giao diện mẫu'),
            trailing: const Icon(Icons.arrow_forward, color: red),
            onTap: () => previewFeature(
              context,
              'ScanPDF Pro',
              'Đây là màn hình minh họa. Bản hiện tại không bán hoặc kích hoạt gói Pro.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Đồng bộ & lưu trữ'),
        const SizedBox(height: 10),
        AccountStorage(
          documents: store.list(owner),
          openCloud: session == null
              ? null
              : () => screen<void>(
                  context,
                  CloudLibrary(session: session, owner: owner),
                ),
        ),
        const SizedBox(height: 20),
        const SectionTitle('Bảo mật & thiết lập'),
        const SizedBox(height: 10),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Chỉnh sửa hồ sơ'),
                subtitle: const Text(
                  'Họ tên, ảnh đại diện, số điện thoại và công ty',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (await screen<bool>(
                            context,
                            ProfileEditor(store: store, owner: owner),
                          ) ==
                          true &&
                      context.mounted) {
                    onRefresh();
                    notice(context, 'Đã lưu thay đổi');
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Đổi mật khẩu'),
                subtitle: const Text('Biểu mẫu dùng thử'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(context, const PasswordScreen()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Xác thực sinh trắc học'),
                subtitle: const Text('Vân tay hoặc mở khóa khuôn mặt · Mẫu'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => previewFeature(
                  context,
                  'Xác thực sinh trắc học',
                  'Mẫu thiết lập khóa ứng dụng. Không yêu cầu quyền và không đọc dữ liệu sinh trắc học.',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Chất lượng quét mặc định'),
                subtitle: Text(
                  'A4 • ${store.highQuality(owner) ? 'Chất lượng cao' : 'Tiêu chuẩn'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final saved = await screen<bool>(
                    context,
                    ScanDefaultsScreen(store: store, owner: owner),
                  );
                  if (saved == true && context.mounted) {
                    onRefresh();
                    notice(context, 'Đã lưu cài đặt');
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Quyền riêng tư'),
                subtitle: const Text('Lưu, chia sẻ và quản lý dữ liệu'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => screen<void>(
                  context,
                  const AccountInfoScreen(type: AccountInfo.privacy),
                ),
              ),
              if (owner == demoOwner || showDesignPreview) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('Xem mẫu giao diện'),
                  subtitle: const Text('Đồng bộ, xác nhận email và OCR'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => screen<void>(context, const DesignPreview()),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
          onPressed: () async {
            if (await confirm(
                  context,
                  title: 'Đăng xuất?',
                  detail: 'Tài liệu đã lưu vẫn được giữ trên thiết bị.',
                  accept: 'Đăng xuất',
                ) &&
                context.mounted) {
              await onSignOut();
            }
          },
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'ScanPDF 1.0.1 • Bản dùng thử',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

String? _accountEmail(BuildContext context, String owner) {
  final session = OnlineScope.of(context);
  return session?.owner == owner ? session?.email : null;
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.store, required this.owner});
  final ScanStore store;
  final String owner;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final initial = widget.store.name(widget.owner, email: email);
  String? email;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    email = _accountEmail(context, widget.owner);
  }

  late final name = TextEditingController(text: initial);
  late final initialPhone = widget.store.phone(widget.owner);
  late final initialCompany = widget.store.company(widget.owner);
  late final phone = TextEditingController(text: initialPhone);
  late final company = TextEditingController(text: initialCompany);
  Uint8List? avatar;
  bool busy = false;
  String? error;
  final form = GlobalKey<FormState>();
  bool get changed =>
      name.text != initial ||
      phone.text != initialPhone ||
      company.text != initialCompany ||
      avatar != null;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    company.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 480,
        maxHeight: 480,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => avatar = bytes);
    } catch (_) {
      if (mounted) notice(context, 'Không thể chọn ảnh đại diện');
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.updateProfile(
        widget.owner,
        name.text.trim(),
        avatar,
        phone: phone.text.trim(),
        company: company.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Không thể lưu hồ sơ. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.store.avatar(widget.owner);
    final bytes = avatar ?? (saved == null ? null : base64Decode(saved));
    return PopScope(
      canPop: !changed && !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || busy) return;
        if (await confirm(
              context,
              title: 'Bỏ thay đổi chưa lưu?',
              detail: 'Hồ sơ hiện tại sẽ được giữ nguyên.',
              accept: 'Bỏ thay đổi',
              cancel: 'Tiếp tục chỉnh sửa',
            ) &&
            context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: blush,
                  foregroundColor: red,
                  foregroundImage: bytes == null ? null : MemoryImage(bytes),
                  child: const Icon(Icons.person_outline, size: 36),
                ),
              ),
              TextButton(
                onPressed: busy ? null : pick,
                child: const Text('Đổi ảnh đại diện'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                onChanged: (_) => setState(() {}),
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Nhập họ và tên' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: email ?? widget.owner,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại (không bắt buộc)',
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty ||
                      RegExp(r'^\+?[0-9 ()-]{6,24}$').hasMatch(value)) {
                    return null;
                  }
                  return 'Nhập số điện thoại hợp lệ';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: company,
                enabled: !busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Công ty (không bắt buộc)',
                ),
                maxLength: 100,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                InfoStrip(icon: Icons.error_outline, text: error!, error: true),
              ],
            ],
          ),
        ),
        bottomNavigationBar: CommandBar(
          child: FilledButton(
            onPressed: busy || !changed ? null : save,
            child: Text(busy ? 'Đang lưu…' : 'Lưu thay đổi'),
          ),
        ),
      ),
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool show = false, otherDevices = true;
  @override
  void dispose() {
    current.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đổi mật khẩu')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle('Bảo vệ tài khoản'),
          const SizedBox(height: 12),
          const InfoStrip(
            icon: Icons.info_outline,
            text:
                'Biểu mẫu dùng thử. Chưa kết nối dịch vụ để cập nhật mật khẩu.',
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: current,
            obscureText: !show,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu hiện tại (mẫu)',
            ),
            validator: (value) =>
                (value?.isEmpty ?? true) ? 'Nhập mật khẩu mẫu hiện tại' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => previewFeature(
                context,
                'Quên mật khẩu?',
                'Gửi liên kết qua email chưa được kết nối.',
              ),
              child: const Text('Quên mật khẩu?'),
            ),
          ),
          TextFormField(
            controller: password,
            onChanged: (_) => setState(() {}),
            obscureText: !show,
            decoration: InputDecoration(
              labelText: 'Mật khẩu mới',
              suffixIcon: IconButton(
                tooltip: show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                icon: Icon(
                  show ? Icons.visibility_off : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => show = !show),
              ),
            ),
            validator: (v) {
              if (!passwordChecks(v ?? '').every((check) => check)) {
                return 'Mật khẩu mẫu chưa đủ yêu cầu';
              }
              return v == current.text
                  ? 'Mật khẩu mới phải khác mật khẩu hiện tại'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          PasswordRules(password.text),
          const SizedBox(height: 12),
          TextFormField(
            controller: confirm,
            obscureText: !show,
            decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu'),
            validator: (v) => v == password.text ? null : 'Mật khẩu không khớp',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Đăng xuất khỏi các thiết bị khác'),
            subtitle: const Text('Tùy chọn minh họa'),
            value: otherDevices,
            onChanged: (value) => setState(() => otherDevices = value ?? false),
          ),
        ],
      ),
    ),
    bottomNavigationBar: CommandBar(
      child: FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            notice(context, 'Biểu mẫu hợp lệ. Mật khẩu chưa được cập nhật.');
          }
        },
        child: const Text('Kiểm tra biểu mẫu'),
      ),
    ),
  );
}
