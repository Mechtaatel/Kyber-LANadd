import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class DiskHelper {
  DiskHelper._();

  static DiskInfo getDiskInfo(String path) {
    final drive = path.substring(0, 3);
    final driveInfo = _getDiskSpaceInfo(drive);

    return DiskInfo(drive, driveInfo.$1, driveInfo.$2);
  }

  static (int, int) _getDiskSpaceInfo(String drive) {
    final freeBytesAvailable = calloc<Uint64>();
    final totalNumberOfBytes = calloc<Uint64>();
    final totalNumberOfFreeBytes = calloc<Uint64>();

    final result = GetDiskFreeSpaceEx(
      TEXT(drive),
      freeBytesAvailable,
      totalNumberOfBytes,
      totalNumberOfFreeBytes,
    );

    var freeSpace = 0;
    var totalSpace = 0;
    if (result != 0) {
      freeSpace = freeBytesAvailable.value;
      totalSpace = totalNumberOfBytes.value;
    }

    free(freeBytesAvailable);
    free(totalNumberOfBytes);
    free(totalNumberOfFreeBytes);

    return (totalSpace, freeSpace);
  }
}

class DiskInfo {
  DiskInfo(this.path, this.totalSpace, this.freeSpace);

  final String path;
  final int totalSpace;
  final int freeSpace;
}
