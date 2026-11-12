import 'package:flutter/material.dart';

const red = Color(0xffe11d2e);
const ink = Color(0xff171717);
const muted = Color(0xff62626a);
const canvas = Color(0xfffcf9f8);
const mist = Color(0xfff6f3f2);
const line = Color(0xffeee8e7);
const blush = Color(0xfffff1f2);
const green = Color(0xff166534);

ThemeData scanTheme({bool dark = false}) {
  final base = ColorScheme.fromSeed(
    seedColor: red,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final palette = base.copyWith(
    primary: dark ? const Color(0xffff616d) : red,
    onPrimary: dark ? ink : Colors.white,
    primaryContainer: blush,
    onPrimaryContainer: const Color(0xff991b1b),
    surface: dark ? ink : Colors.white,
    onSurface: dark ? Colors.white : ink,
    onSurfaceVariant: dark ? const Color(0xffc9c9cf) : muted,
    outlineVariant: dark ? const Color(0xff424248) : line,
  );
  final corner = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: palette,
    scaffoldBackgroundColor: dark ? ink : canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: palette.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff252527) : mist,
      border: OutlineInputBorder(
        borderRadius: corner,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: corner,
        borderSide: BorderSide(color: palette.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: corner),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: corner),
        side: BorderSide(color: palette.outlineVariant),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    navigationBarTheme: const NavigationBarThemeData(
      height: 70,
      backgroundColor: Colors.white,
      indicatorColor: blush,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

Future<void> previewFeature(
  BuildContext context,
  String title,
  String detail,
) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    icon: const Icon(Icons.science_outlined, color: red),
    title: Text(title),
    content: Text(detail),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('Đóng'),
      ),
    ],
  ),
);

List<bool> passwordChecks(String value) => [
  value.length >= 8,
  RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value),
  RegExp(r'[0-9]').hasMatch(value),
  RegExp(r'[^a-zA-Z0-9\s]').hasMatch(value),
];

class PasswordRules extends StatelessWidget {
  const PasswordRules(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) {
    final checks = passwordChecks(value);
    final score = checks.where((check) => check).length;
    const labels = [
      'Ít nhất 8 ký tự',
      'Có chữ hoa và chữ thường',
      'Có chữ số',
      'Có ký tự đặc biệt',
    ];
    return Panel(
      color: mist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Độ mạnh mật khẩu · ${['Chưa an toàn', 'Yếu', 'Trung bình', 'Khá mạnh', 'Mạnh'][score]}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: score / 4,
            color: score == 4 ? green : red,
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    checks[i]
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: checks[i] ? green : muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<T?> screen<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void notice(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String detail,
  required String accept,
  String cancel = 'Hủy',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accept),
          ),
        ],
      ),
    ) ??
    false;

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: red,
      borderRadius: BorderRadius.circular(size * .24),
      boxShadow: [
        BoxShadow(
          color: red.withValues(alpha: .18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Icon(
      Icons.document_scanner_outlined,
      color: Colors.white,
      size: size * .56,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -.45,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(
          subtitle!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    ],
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.borderColor = line,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color, borderColor;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: blush,
            child: Icon(icon, color: red, size: 27),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({
    super.key,
    required this.icon,
    required this.text,
    this.error = false,
  });
  final IconData icon;
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Panel(
    color: error ? blush : mist,
    borderColor: error ? const Color(0xfffecdd3) : line,
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: error ? red : muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: error ? const Color(0xff991b1b) : muted,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class CommandBar extends StatelessWidget {
  const CommandBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: child,
      ),
    ),
  );
}
