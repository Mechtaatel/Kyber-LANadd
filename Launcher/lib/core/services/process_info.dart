import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

base class _TOKEN_ELEVATION extends Struct {
  @Uint32()
  external int TokenIsElevated;
}

class ProcessHelper {
  ProcessHelper._();

  static const TokenElevation = 20;

  static bool isRunningAsAdmin() {
    final tokenHandle = calloc<HANDLE>();
    final elevation = calloc<_TOKEN_ELEVATION>();
    final returnLength = calloc<DWORD>();

    try {
      if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, tokenHandle) ==
          0) {
        throw Exception(
          'Failed to open process token. Error: ${GetLastError()}',
        );
      }

      if (GetTokenInformation(
            tokenHandle.value,
            TokenElevation,
            elevation,
            sizeOf<_TOKEN_ELEVATION>(),
            returnLength,
          ) ==
          0) {
        throw Exception(
          'Failed to get token information. Error: ${GetLastError()}',
        );
      }

      return elevation.ref.TokenIsElevated != 0;
    } finally {
      CloseHandle(tokenHandle.value);
      calloc
        ..free(tokenHandle)
        ..free(elevation)
        ..free(returnLength);
    }
  }
}
