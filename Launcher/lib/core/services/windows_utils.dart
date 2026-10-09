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
      nullptr,
      COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
    );
    try {
      info.ref
        ..cbSize = sizeOf<SHELLEXECUTEINFO>()
        ..fMask = _seeMaskNoAsync
        ..lpVerb = verb
        ..lpFile = file
        ..lpParameters = arguments
        ..lpDirectory = directory
        ..nShow = SW_SHOWNORMAL;
      if (ShellExecuteEx(info) == 0) {
        final error = GetLastError();
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
    final RtlGetVersion = ntdll
        .lookupFunction<_RtlGetVersionC, _RtlGetVersionDart>('RtlGetVersion');
    final osVersionInfo = calloc<OSVERSIONINFO>();

    try {
      osVersionInfo.ref.dwOSVersionInfoSize = sizeOf<OSVERSIONINFO>();
      final result = RtlGetVersion(osVersionInfo);

      if (result == 0) {
        final major = osVersionInfo.ref.dwMajorVersion;
        final minor = osVersionInfo.ref.dwMinorVersion;

        if (major == 6 && minor == 1) {
          return true;
        }
      }

      return false;
    } finally {
      calloc.free(osVersionInfo);
      ntdll.close();
    }
  }

  static bool _isDllPresent(String dllName) {
    final ptr = dllName.toNativeUtf16();
    final hModule = LoadLibraryEx(ptr, 0, LOAD_LIBRARY_SEARCH_SYSTEM32);
    calloc.free(ptr);

    if (hModule != NULL) {
      FreeLibrary(hModule);
      return true;
    }
    return false;
  }

  static bool get isVcRuntimeInstalled {
    return _isDllPresent('vcruntime140.dll') || _isDllPresent('msvcp140.dll');
  }
}
