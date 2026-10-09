import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

typedef _RtlGetVersionC = Int32 Function(Pointer<OSVERSIONINFO>);
typedef _RtlGetVersionDart = int Function(Pointer<OSVERSIONINFO>);

// Wait for the elevated installer to start before closing the launcher.
const _seeMaskNoAsync = 0x00000100;

class WindowsUtils {
  WindowsUtils._();

  static void startUpdateInstaller(String installerPath) {
    final verb = 'runas'.toNativeUtf16();
    final file = installerPath.toNativeUtf16();
    final directory = p.dirname(installerPath).toNativeUtf16();
    final arguments =
        ('/SILENT /NORESTART /CLOSEAPPLICATIONS /NOFORCECLOSEAPPLICATIONS '
                '/LANADDUPDATE=1 /DIR="${p.dirname(Platform.resolvedExecutable)}" '
                '/LOG="${p.join(p.dirname(installerPath), 'install.log')}"')
            .toNativeUtf16();
    final info = calloc<SHELLEXECUTEINFO>();
    final comResult = CoInitializeEx(
      COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
    );
    try {
      info.ref
        ..cbSize = sizeOf<SHELLEXECUTEINFO>()
        ..fMask = _seeMaskNoAsync
        ..lpVerb = PWSTR(verb)
        ..lpFile = PWSTR(file)
        ..lpParameters = PWSTR(arguments)
        ..lpDirectory = PWSTR(directory)
        ..nShow = SW_SHOWNORMAL;
      final result = ShellExecuteEx(info);
      if (!result.value) {
        final error = result.error;
        throw StateError(
          error == ERROR_CANCELLED
              ? 'Installation was cancelled. The launcher is still open.'
              : 'Could not start the LAN ADD installer (Windows error $error).',
        );
      }
    } finally {
      if (comResult >= 0) CoUninitialize();
      calloc
        ..free(info)
        ..free(verb)
        ..free(file)
        ..free(directory)
        ..free(arguments);
    }
  }

  static bool isWindowsCompMode() {
    if (!Platform.isWindows) {
      return false;
    }

    final ntdll = DynamicLibrary.open('ntdll.dll');
    final rtlGetVersion = ntdll
        .lookupFunction<_RtlGetVersionC, _RtlGetVersionDart>('RtlGetVersion');

    return using((arena) {
      final info = arena<OSVERSIONINFO>()
        ..ref.dwOSVersionInfoSize = sizeOf<OSVERSIONINFO>();

      if (rtlGetVersion(info) != 0) {
        return false;
      }

      return info.ref.dwMajorVersion == 6 && info.ref.dwMinorVersion == 1;
    });
  }

  static bool _isDllPresent(String dllName) => using((arena) {
    final result = LoadLibraryEx(
      arena.pcwstr(dllName),
      LOAD_LIBRARY_SEARCH_SYSTEM32,
    );

    if (result.value.isNull) {
      return false;
    }

    FreeLibrary(result.value);
    return true;
  });

  static bool get isVcRuntimeInstalled =>
      _isDllPresent('vcruntime140.dll') || _isDllPresent('msvcp140.dll');
}
