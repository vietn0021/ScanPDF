import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'common.dart';
import 'library.dart';
import 'online/api_client.dart';
import 'online/session_store.dart';
import 'scan_data.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScanPdfApp());
}

class ScanPdfApp extends StatefulWidget {
  const ScanPdfApp({super.key, this.store});
  final ScanStore? store;

  @override
  State<ScanPdfApp> createState() => _ScanPdfAppState();
}

class _ScanPdfAppState extends State<ScanPdfApp> {
  late Future<ScanStore> _load;
  String? _session;
  OnlineSession? _online;
  @override
  void initState() {
    super.initState();
    _load = _start();
  }

  Future<ScanStore> _start() async {
    final api = widget.store == null ? ScanApi.configured() : null;
    _online = api == null ? null : OnlineSession(api);
    final store =
        widget.store ?? ScanStore(await SharedPreferences.getInstance());
    await _online?.restore();
    return store;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ScanPDF',
    theme: scanTheme(),
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => _online == null
        ? child!
        : OnlineScope(session: _online!, child: child!),
    home: FutureBuilder<ScanStore>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: StatePanel(
              icon: Icons.error_outline,
              title: 'Không thể mở ScanPDF',
              message: 'Kiểm tra vùng lưu trữ rồi thử lại.',
              action: FilledButton(
                onPressed: () => setState(() => _load = _start()),
                child: const Text('Thử lại'),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const StartupScreen();
        }
        final store = snapshot.data!;
        final online = _online;
        final account =
            online?.owner ??
            _session ??
            (online == null || store.account == demoOwner
                ? store.account
                : null);
        if (account == null) {
          return AuthScreen(
            online: online,
            onOnlineLogin: () {
              if (mounted) setState(() {});
            },
            onSignIn: (email, {required remember, name}) async {
              if (name != null) await store.updateProfile(email, name, null);
              if (remember) await store.signIn(email);
              if (mounted) setState(() => _session = email);
            },
          );
        }
        return HomeScreen(
          key: ValueKey(account),
          store: store,
          owner: account,
          onSignOut: () async {
            if (online?.owner == account) {
              final pending = online!.logout();
              await store.signOut();
              if (mounted) setState(() => _session = null);
              final revoked = await pending;
              if (!revoked && context.mounted) {
                notice(
                  context,
                  'Đã đăng xuất trên máy. Chưa xác nhận thu hồi phiên trên máy chủ.',
                );
              }
              return;
            }
            await store.signOut();
            if (mounted) setState(() => _session = null);
          },
        );
      },
    ),
  );
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, this.preview = false});
  final bool preview;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              if (preview)
                const InfoStrip(
                  icon: Icons.science_outlined,
                  text: 'Màn hình khởi động · Dữ liệu mẫu',
                ),
              const SizedBox(height: 20),
              const Center(child: BrandMark(size: 80)),
              const SizedBox(height: 16),
              const Text(
                'ScanPDF',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
              const Text(
                'Máy quét tài liệu và PDF di động',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Panel(
                child: Column(
                  children: [
                    if (preview)
                      const Icon(Icons.sync, color: red, size: 32)
                    else
                      const CircularProgressIndicator(
                        semanticsLabel: 'Đang mở ScanPDF',
                      ),
                    const SizedBox(height: 12),
                    Text(
                      preview
                          ? 'Đang kiểm tra phiên đăng nhập…'
                          : 'Đang mở ScanPDF…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (preview) ...[
                const SizedBox(height: 14),
                const Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.check_circle_outline, color: green),
                        title: Text('Có phiên mẫu'),
                        subtitle: Text('Mở thư viện tài liệu'),
                        trailing: Icon(Icons.folder_outlined),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.login, color: red),
                        title: Text('Chưa có phiên'),
                        subtitle: Text('Mở màn hình đăng nhập'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const InfoStrip(
                  icon: Icons.wifi_off,
                  text: 'Quét và tạo PDF vẫn dùng được ngoại tuyến.',
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
