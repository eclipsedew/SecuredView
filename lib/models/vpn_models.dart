class ServerConfig {
  final String id;
  final String name;
  final String country;
  final String countryCode;
  final String endpoint;
  final int port;
  final String publicKey;
  final String? ipAddress;
  final String? dns;
  final bool isPremium;
  final int sortOrder;
  final double latitude;
  final double longitude;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.endpoint,
    required this.port,
    required this.publicKey,
    this.ipAddress,
    this.dns,
    required this.isPremium,
    required this.sortOrder,
    this.latitude = 0,
    this.longitude = 0,
  });

  String get flagEmoji {
    final code = countryCode.toUpperCase();
    if (code.length != 2) return '🌐';
    return String.fromCharCodes(
      code.codeUnits.map((c) => 0x1F1E6 - 65 + c),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'country': country,
    'countryCode': countryCode,
    'endpoint': endpoint,
    'port': port,
    'publicKey': publicKey,
    'ipAddress': ipAddress,
    'dns': dns,
    'isPremium': isPremium,
    'sortOrder': sortOrder,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    country: json['country'] ?? '',
    countryCode: json['countryCode'] ?? '',
    endpoint: json['endpoint'] ?? '',
    port: json['port'] ?? 51820,
    publicKey: json['publicKey'] ?? '',
    ipAddress: json['ipAddress'],
    dns: json['dns'],
    isPremium: json['isPremium'] ?? false,
    sortOrder: json['sortOrder'] ?? 0,
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
  );

  ServerConfig copyWith({
    String? id,
    String? name,
    String? country,
    String? countryCode,
    String? endpoint,
    int? port,
    String? publicKey,
    String? ipAddress,
    String? dns,
    bool? isPremium,
    int? sortOrder,
    double? latitude,
    double? longitude,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      endpoint: endpoint ?? this.endpoint,
      port: port ?? this.port,
      publicKey: publicKey ?? this.publicKey,
      ipAddress: ipAddress ?? this.ipAddress,
      dns: dns ?? this.dns,
      isPremium: isPremium ?? this.isPremium,
      sortOrder: sortOrder ?? this.sortOrder,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

class ConnectionStats {
  final int bytesSent;
  final int bytesReceived;
  final Duration connectedDuration;

  const ConnectionStats({
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.connectedDuration = Duration.zero,
  });

  String get formattedSent {
    if (bytesSent < 1024) return '$bytesSent B';
    if (bytesSent < 1048576) return '${(bytesSent / 1024).toStringAsFixed(1)} KB';
    if (bytesSent < 1073741824) return '${(bytesSent / 1048576).toStringAsFixed(1)} MB';
    return '${(bytesSent / 1073741824).toStringAsFixed(2)} GB';
  }

  String get formattedReceived {
    if (bytesReceived < 1024) return '$bytesReceived B';
    if (bytesReceived < 1048576) return '${(bytesReceived / 1024).toStringAsFixed(1)} KB';
    if (bytesReceived < 1073741824) return '${(bytesReceived / 1048576).toStringAsFixed(1)} MB';
    return '${(bytesReceived / 1073741824).toStringAsFixed(2)} GB';
  }

  String get formattedDuration {
    final h = connectedDuration.inHours;
    final m = connectedDuration.inMinutes % 60;
    final s = connectedDuration.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get uploadSpeed => formattedSent;
  String get downloadSpeed => formattedReceived;
  String get durationText => formattedDuration;
}

enum VPNState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum SubscriptionTier {
  free,
  premium,
}

class PremiumPlan {
  final String id;
  final String name;
  final int days;
  final double priceUSD;
  final String priceDisplay;

  const PremiumPlan({
    required this.id,
    required this.name,
    required this.days,
    required this.priceUSD,
    required this.priceDisplay,
  });
}

class UserAccount {
  final String accountId;
  final SubscriptionTier tier;
  final DateTime? premiumExpiry;
  final List<String> deviceIds;
  final DateTime createdAt;
  final int deviceCount;

  const UserAccount({
    required this.accountId,
    this.tier = SubscriptionTier.free,
    this.premiumExpiry,
    this.deviceIds = const [],
    required this.createdAt,
    this.deviceCount = 0,
  });

  bool get isPremiumActive {
    if (tier != SubscriptionTier.premium) return false;
    if (premiumExpiry == null) return false;
    return DateTime.now().isBefore(premiumExpiry!);
  }

  int get devicesConnected => deviceCount > 0 ? deviceCount : deviceIds.length;
  bool get canAddDevice => devicesConnected < 2;

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'tier': tier.name,
    'premiumExpiry': premiumExpiry?.toIso8601String(),
    'deviceIds': deviceIds,
    'createdAt': createdAt.toIso8601String(),
    'deviceCount': deviceCount,
  };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    accountId: json['accountId'] ?? '',
    tier: SubscriptionTier.values.firstWhere(
      (e) => e.name == json['tier'],
      orElse: () => SubscriptionTier.free,
    ),
    premiumExpiry: json['premiumExpiry'] != null
        ? DateTime.parse(json['premiumExpiry'])
        : null,
    deviceIds: List<String>.from(json['deviceIds'] ?? []),
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
    deviceCount: json['deviceCount'] ?? 0,
  );
}