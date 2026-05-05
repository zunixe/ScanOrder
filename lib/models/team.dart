import 'package:json_annotation/json_annotation.dart';

part 'team.g.dart';

@JsonSerializable()
class Team {
  final String id;
  final String name;
  @JsonKey(name: 'invite_code')
  final String inviteCode;
  @JsonKey(name: 'created_by')
  final String createdBy;
  @JsonKey(name: 'created_at', fromJson: _isoToDateTime, toJson: _dateTimeToIso)
  final DateTime createdAt;

  Team({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdBy,
    required this.createdAt,
  });

  factory Team.fromJson(Map<String, dynamic> map) => _$TeamFromJson(map);
  Map<String, dynamic> toJson() => _$TeamToJson(this);

  factory Team.fromMap(Map<String, dynamic> map) => _$TeamFromJson(map);
  Map<String, dynamic> toMap() => _$TeamToJson(this);
}

@JsonSerializable()
class TeamMember {
  final String id;
  @JsonKey(name: 'team_id')
  final String teamId;
  @JsonKey(name: 'user_id')
  final String userId;
  final String role;
  @JsonKey(name: 'joined_at', fromJson: _isoToDateTime, toJson: _dateTimeToIso)
  final DateTime joinedAt;
  final String? email;

  TeamMember({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.email,
  });

  factory TeamMember.fromJson(Map<String, dynamic> map) => _$TeamMemberFromJson(map);
  Map<String, dynamic> toJson() => _$TeamMemberToJson(this);

  factory TeamMember.fromMap(Map<String, dynamic> map) => _$TeamMemberFromJson(map);
  Map<String, dynamic> toMap() => _$TeamMemberToJson(this);
}

DateTime _isoToDateTime(Object? v) {
  if (v == null) return DateTime.now();
  if (v is String) return DateTime.parse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return DateTime.now();
}

String _dateTimeToIso(DateTime dt) => dt.toIso8601String();
