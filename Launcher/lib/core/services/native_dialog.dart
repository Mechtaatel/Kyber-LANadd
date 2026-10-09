import 'package:win32/win32.dart';

void showWebViewDialog() {
  final titlePtr = TEXT('WebView2 Error');
  final messagePtr = TEXT(
    'WebView2 is required to run this application. Please install it from https://go.microsoft.com/fwlink/?linkid=2135547',
  );

  MessageBox(
    NULL,
    messagePtr,
    titlePtr,
    MESSAGEBOX_STYLE.MB_ICONERROR | MESSAGEBOX_STYLE.MB_OK,
  );

  free(titlePtr);
  free(messagePtr);
}

void showRustLibMissingDialog() {
  final titlePtr = TEXT('Native Library Missing');
  final messagePtr = TEXT(
    'The required native library is missing. This can be caused by antivirus software removing the file. Please exclude the application from your antivirus and reinstall.',
  );

  MessageBox(
    NULL,
    messagePtr,
    titlePtr,
    MESSAGEBOX_STYLE.MB_ICONERROR | MESSAGEBOX_STYLE.MB_OK,
  );

  free(titlePtr);
  free(messagePtr);
}