import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:kyber/gen/Proto/kyber_interface.pbgrpc.dart';
import 'package:kyber/kyber.dart' hide Server;
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/models/maxima_instance.dart';
import 'package:kyber_cli/utils/services/level_declaration_service.dart';
import 'package:kyber_cli/utils/windows_env.dart';
import 'package:logging/logging.dart';

InitializeRequest? _initializeRequest;

class LauncherService extends LauncherCommonServiceBase {
  @override
  Future<InitializeRequest> initialize(ServiceCall call, Empty request) {
    return Future.value(_initializeRequest);
  }

  @override
  Future<CustomLevelDataResponse> getCustomLevelData(
    ServiceCall call,
    CustomLevelDataRequest req,
  ) {
    if (!sl.isRegistered<MaximaGameInstance>()) {
      throw Exception(
        'MaximaGameInstance is not registered in the service locator',
      );
    }

    final instance = sl.get<MaximaGameInstance>();
    final levelService = sl.get<LevelDeclarationService>();
    final map = levelService.getMapByMode(
      map: req.map,
      mode: req.mode,
      mods: instance.gameplayMods,
    );
    final mode = levelService.getModeName(
      mode: req.mode,
      mods: instance.gameplayMods,
    );

    return Future.value(
      CustomLevelDataResponse(mapName: map?.name, modeName: mode),
    );
  }

  @override
  Future<Empty> onServerJoined(ServiceCall call, Empty request) {
    return Future.value(.new());
  }

  @override
  Future<Empty> onServerLeft(ServiceCall call, Empty request) {
    return Future.value(.new());
  }
}

class KyberGRPCServer {
  final _logger = Logger('grpc_server');

  Server? _server;

  InitializeRequest getInitializeRequest() {
    final request = _initializeRequest;
    if (request == null) {
      throw Exception('Initialize request is not set');
    }

    return _initializeRequest!;
  }

  void setInitializeRequest(InitializeRequest request) {
    _initializeRequest = request;
  }

  Future<void> start() async {
    _logger.info('Starting gRPC server');
    _server = Server.create(
      services: [LauncherService()],
      codecRegistry: CodecRegistry(codecs: const [GzipCodec()]),
      errorHandler: (error, trace) {
        _logger.severe('An error occurred: $error', error, trace);
      },
    );

    final port = await KyberNetworkHelper.findAvailablePort();
    await _server?.serve(address: InternetAddress.loopbackIPv4, port: port);
    Env.set('KYBER_LAUNCHER_PORT', port.toString());

    _logger.info('Server listening on port $port');
  }

  void dispose() {
    _server?.shutdown();
  }
}
