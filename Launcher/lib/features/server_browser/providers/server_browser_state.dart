part of 'server_browser_cubit.dart';

class ServerBrowserState {
  const ServerBrowserState({
    this.selectedServer,
    this.joiningServer,
  });

  final Object? selectedServer;
  final Server? joiningServer;

  ServerBrowserState copyWith({
    Object? selectedServer,
    Server? joiningServer,
  }) {
    return ServerBrowserState(
      selectedServer: selectedServer ?? this.selectedServer,
      joiningServer: joiningServer ?? this.joiningServer,
    );
  }
}
