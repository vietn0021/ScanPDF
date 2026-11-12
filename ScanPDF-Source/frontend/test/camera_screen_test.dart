import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanpdf/camera_screen.dart';
import 'package:scanpdf/common.dart';

void main() {
  testWidgets(
    'granting permission resumes the original camera initialization',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/camera');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final permission = Completer<Map<String, Object>>();
      var opens = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'availableCameras':
            return [
              {'name': 'back', 'lensFacing': 'back', 'sensorOrientation': 90},
            ];
          case 'create':
            opens++;
            return permission.future;
          case 'initialize':
            await messenger.handlePlatformMessage(
              'flutter.io/cameraPlugin/camera1',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('initialized', {
                  'previewWidth': 640.0,
                  'previewHeight': 480.0,
                  'exposureMode': 'auto',
                  'exposurePointSupported': false,
                  'focusMode': 'auto',
                  'focusPointSupported': false,
                }),
              ),
              null,
            );
            return null;
          case 'dispose':
            return null;
          default:
            fail('Unexpected camera method ${call.method}');
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump();
      expect(opens, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(opens, 1);

      permission.complete({'cameraId': 1});
      await tester.pumpAndSettle();
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final shutter = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Chụp ảnh',
      );
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('camera controls stay below the loading and error states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1536, 728);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const channel = MethodChannel('plugins.flutter.io/camera');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final opening = Completer<List<Object?>>();
    messenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'availableCameras');
      return opening.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
    final bar = tester.getRect(find.byType(CommandBar));
    expect(bar.height, lessThan(100));
    expect(bar.bottom, 728);
    expect(
      tester.getRect(find.byType(CircularProgressIndicator)).bottom,
      lessThan(bar.top),
    );

    opening.complete([]);
    await tester.pumpAndSettle();
    expect(
      find.text('Không tìm thấy camera trên thiết bị này.'),
      findsOneWidget,
    );
    expect(tester.getRect(find.text('Thử lại')).bottom, lessThan(bar.top));
    expect(tester.takeException(), isNull);
  });
}
