import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

class TaskbarIconHelper {
  TaskbarIconHelper._();

  static final _logger = Logger('taskbar_icon');
  static int? _defaultIcon;

  static Future<Uint8List?> _getIcon() async {
    try {
      final response = await Dio()
          .get<Uint8List>(
            'https://s3.kyber.gg/frontend-assets/launcher_icon.ico',
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
            ),
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw Exception('Request timed out');
            },
          );

      return response.data != null ? Uint8List.fromList(response.data!) : null;
    } catch (e) {
      return null;
    }
  }

  static void _resetIcon() {
    if (_defaultIcon == null) {
      return;
    }

    SetClassLongPtr(GetConsoleWindow(), GCL_HICON, _defaultIcon!);
    SendMessage(GetConsoleWindow(), WM_SETICON, ICON_BIG, _defaultIcon!);
    SendMessage(GetConsoleWindow(), WM_SETICON, ICON_SMALL, _defaultIcon!);
  }

  static void setWindowIcon() async {
    if (!Platform.isWindows) {
      return;
    }

    final icon = await _getIcon();
    if (icon == null && _defaultIcon != null) {
      return _resetIcon();
    } else if (icon == null) {
      return;
    }

    final hwnd = FindWindow(
      TEXT('FLUTTER_RUNNER_WIN32_WINDOW'),
      TEXT('KYBER Launcher'),
    );
    if (hwnd == 0) {
      _logger.severe('Failed to obtain the Flutter window handle.');
      return;
    }

    _defaultIcon = GetClassLongPtr(hwnd, GCL_HICON);

    final tmpDir = await getTemporaryDirectory();
    final tmpFile = join(tmpDir.path, 'launcher_icon', 'launcher_icon.ico');

    if (!Directory(dirname(tmpFile)).existsSync()) {
      await Directory(dirname(tmpFile)).create(recursive: true);
    }

    await File(tmpFile).writeAsBytes(icon.toList());

    final iconPathPtr = tmpFile.toNativeUtf16();
    final iconHandle = LoadImage(
      0,
      iconPathPtr,
      IMAGE_ICON,
      32,
      32,
      LR_LOADFROMFILE,
    );

    calloc.free(iconPathPtr);

    if (iconHandle == 0) {
      final error = GetLastError();
      _logger.severe('Failed to load icon from file. Error code: $error');
      return;
    }

    SetClassLongPtr(hwnd, GCL_HICON, iconHandle);
    SendMessage(hwnd, WM_SETICON, ICON_BIG, iconHandle);
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, iconHandle);
  }
}
