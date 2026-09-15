class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.accessToken = '',
    this.instanceId,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String accessToken;
  final String? instanceId;

  ServerProfile copyWith({
    String? name,
    String? baseUrl,
    String? accessToken,
    String? instanceId,
  }) => ServerProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    accessToken: accessToken ?? this.accessToken,
    instanceId: instanceId ?? this.instanceId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'accessToken': accessToken,
    if (instanceId != null) 'instanceId': instanceId,
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    accessToken: json['accessToken'] as String? ?? '',
    instanceId: json['instanceId'] as String?,
  );
}

class InternetServerInfo {
  const InternetServerInfo({
    required this.instanceId,
    required this.name,
    required this.maxRoomParticipants,
    required this.protocolVersion,
    this.adminListeningSupported = false,
  });

  final String instanceId;
  final String name;
  final int maxRoomParticipants;
  final int protocolVersion;
  final bool adminListeningSupported;

  factory InternetServerInfo.fromJson(Map<String, dynamic> json) =>
      InternetServerInfo(
        instanceId: json['instanceId'] as String,
        name: json['name'] as String? ?? 'DawnMesh Server',
        maxRoomParticipants: json['maxRoomParticipants'] as int? ?? 25,
        protocolVersion: json['protocolVersion'] as int? ?? 1,
        adminListeningSupported:
            json['adminListeningSupported'] as bool? ?? false,
      );
}

class InternetRoomSummary {
  const InternetRoomSummary({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.maxParticipants,
    required this.hostNickname,
    this.isHost = false,
    this.adminListening = false,
    this.adminListeningAvailable = false,
  });

  final String id;
  final String name;
  final int memberCount;
  final int maxParticipants;
  final String hostNickname;
  final bool isHost;
  final bool adminListening;
  final bool adminListeningAvailable;

  factory InternetRoomSummary.fromJson(Map<String, dynamic> json) =>
      InternetRoomSummary(
        id: json['id'] as String,
        name: json['name'] as String? ?? '网络房间',
        memberCount: json['memberCount'] as int? ?? 0,
        maxParticipants: json['maxParticipants'] as int? ?? 25,
        hostNickname: json['hostNickname'] as String? ?? '',
        isHost: json['isHost'] as bool? ?? false,
        adminListening: json['adminListening'] as bool? ?? false,
        adminListeningAvailable:
            json['adminListeningAvailable'] as bool? ?? false,
      );
}

class InternetConnectionGrant {
  const InternetConnectionGrant({
    required this.room,
    required this.memberId,
    required this.livekitUrl,
    required this.livekitToken,
    required this.resumeToken,
    required this.eventsUrl,
  });

  final InternetRoomSummary room;
  final String memberId;
  final String livekitUrl;
  final String livekitToken;
  final String resumeToken;
  final String eventsUrl;

  factory InternetConnectionGrant.fromJson(Map<String, dynamic> json) =>
      InternetConnectionGrant(
        room: InternetRoomSummary.fromJson(
          json['room'] as Map<String, dynamic>,
        ),
        memberId: json['memberId'] as String,
        livekitUrl: json['livekitUrl'] as String,
        livekitToken: json['livekitToken'] as String,
        resumeToken: json['resumeToken'] as String,
        eventsUrl: json['eventsUrl'] as String,
      );
}

class InternetAdmissionGrant {
  const InternetAdmissionGrant({
    required this.room,
    required this.admissionId,
    required this.memberId,
    required this.resumeToken,
    required this.eventsUrl,
  });

  final InternetRoomSummary room;
  final String admissionId;
  final String memberId;
  final String resumeToken;
  final String eventsUrl;

  factory InternetAdmissionGrant.fromJson(Map<String, dynamic> json) =>
      InternetAdmissionGrant(
        room: InternetRoomSummary.fromJson(
          json['room'] as Map<String, dynamic>,
        ),
        admissionId: json['admissionId'] as String,
        memberId: json['memberId'] as String,
        resumeToken: json['resumeToken'] as String,
        eventsUrl: json['eventsUrl'] as String,
      );
}

class InternetMember {
  const InternetMember({
    required this.id,
    required this.nickname,
    required this.isHost,
    required this.canSpeak,
    this.sortOrder = 0,
    this.isSpeaking = false,
  });

  final String id;
  final String nickname;
  final bool isHost;
  final bool canSpeak;
  final int sortOrder;
  final bool isSpeaking;

  static int compareStable(InternetMember a, InternetMember b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  }
}
