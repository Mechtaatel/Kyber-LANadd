import 'package:kyber_launcher/features/kyber/helper/kyber_status_helper.dart';

class LightswitchStatus {
  LightswitchStatus({
    required this.status,
    required this.environments,
    required this.defaultEnvironment,
    this.message,
  });

  factory LightswitchStatus.fromJson(Map<String, dynamic> json) =>
      LightswitchStatus(
        status: KyberStatusEnum.values.firstWhere(
          (e) =>
              e.toString().split('.').last ==
              (json['status'] as String).toLowerCase(),
        ),
        message: json['message'] as String?,
        environments: List<Environment>.from(
          (json['environments'] as List<dynamic>).map(
            (x) => Environment.fromJson(x as Map<String, dynamic>),
          ),
        ),
        defaultEnvironment: json['defaultEnvironment'] as String,
      );

  factory LightswitchStatus.defaultStatus() => LightswitchStatus(
    status: KyberStatusEnum.up,
    environments: [],
    defaultEnvironment: 'prod',
  );

  KyberStatusEnum status;
  String? message;
  List<Environment> environments;
  String defaultEnvironment;

  Map<String, dynamic> toJson() => {
    'status': status,
    'message': message,
    'environments': List<dynamic>.from(environments.map((x) => x.toJson())),
    'defaultEnvironment': defaultEnvironment,
  };
}

class Environment {
  Environment({
    required this.id,
    required this.name,
    required this.apiRoot,
    required this.apiRpc,
  });

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
    id: json['id'] as String,
    name: json['name'] as String,
    apiRoot: json['apiRoot'] as String,
    apiRpc: json['apiRpc'] as String,
  );
  String id;
  String name;
  String apiRoot;
  String apiRpc;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiRoot': apiRoot,
    'apiRpc': apiRpc,
  };
}
