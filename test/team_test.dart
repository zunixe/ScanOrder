import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/models/team.dart';

void main() {
  group('Team', () {
    final now = DateTime(2026, 5, 6, 10, 30);

    test('creates with required fields', () {
      final team = Team(
        id: 'team-1',
        name: 'My Team',
        inviteCode: 'INVITE123',
        createdBy: 'admin',
        createdAt: now,
      );
      expect(team.id, 'team-1');
      expect(team.name, 'My Team');
      expect(team.inviteCode, 'INVITE123');
      expect(team.createdBy, 'admin');
      expect(team.createdAt, now);
    });

    test('toJson and fromJson round-trip', () {
      final team = Team(
        id: 'team-2',
        name: 'Test Team',
        inviteCode: 'CODE456',
        createdBy: 'user1',
        createdAt: now,
      );
      final json = team.toJson();
      final restored = Team.fromJson(json);
      expect(restored.id, team.id);
      expect(restored.name, team.name);
      expect(restored.inviteCode, team.inviteCode);
      expect(restored.createdBy, team.createdBy);
      expect(restored.createdAt.millisecondsSinceEpoch, team.createdAt.millisecondsSinceEpoch);
    });

    test('toMap and fromMap round-trip', () {
      final team = Team(
        id: 'team-3',
        name: 'Map Team',
        inviteCode: 'MAP789',
        createdBy: 'user2',
        createdAt: now,
      );
      final map = team.toMap();
      final restored = Team.fromMap(map);
      expect(restored.id, team.id);
      expect(restored.name, team.name);
      expect(restored.inviteCode, team.inviteCode);
      expect(restored.createdBy, team.createdBy);
    });

    test('toJson includes invite_code with underscore', () {
      final team = Team(
        id: 'team-4',
        name: 'Key Team',
        inviteCode: 'KEY999',
        createdBy: 'admin',
        createdAt: now,
      );
      final json = team.toJson();
      expect(json['invite_code'], 'KEY999');
      expect(json['created_by'], 'admin');
      expect(json['created_at'], isA<String>());
    });
  });

  group('TeamMember', () {
    final now = DateTime(2026, 5, 6, 11, 0);

    test('creates with required fields', () {
      final member = TeamMember(
        id: 'member-1',
        teamId: 'team-1',
        userId: 'user-1',
        role: 'admin',
        joinedAt: now,
      );
      expect(member.id, 'member-1');
      expect(member.teamId, 'team-1');
      expect(member.userId, 'user-1');
      expect(member.role, 'admin');
      expect(member.joinedAt, now);
      expect(member.email, isNull);
    });

    test('creates with optional email', () {
      final member = TeamMember(
        id: 'member-2',
        teamId: 'team-1',
        userId: 'user-2',
        role: 'member',
        joinedAt: now,
        email: 'user@example.com',
      );
      expect(member.email, 'user@example.com');
    });

    test('toJson and fromJson round-trip', () {
      final member = TeamMember(
        id: 'member-3',
        teamId: 'team-2',
        userId: 'user-3',
        role: 'member',
        joinedAt: now,
        email: 'test@example.com',
      );
      final json = member.toJson();
      final restored = TeamMember.fromJson(json);
      expect(restored.id, member.id);
      expect(restored.teamId, member.teamId);
      expect(restored.userId, member.userId);
      expect(restored.role, member.role);
      expect(restored.email, member.email);
      expect(restored.joinedAt.millisecondsSinceEpoch, member.joinedAt.millisecondsSinceEpoch);
    });

    test('toMap and fromMap round-trip', () {
      final member = TeamMember(
        id: 'member-4',
        teamId: 'team-3',
        userId: 'user-4',
        role: 'admin',
        joinedAt: now,
      );
      final map = member.toMap();
      final restored = TeamMember.fromMap(map);
      expect(restored.id, member.id);
      expect(restored.teamId, member.teamId);
      expect(restored.userId, member.userId);
      expect(restored.role, member.role);
    });

    test('toJson includes underscore keys', () {
      final member = TeamMember(
        id: 'member-5',
        teamId: 'team-4',
        userId: 'user-5',
        role: 'member',
        joinedAt: now,
      );
      final json = member.toJson();
      expect(json['team_id'], 'team-4');
      expect(json['user_id'], 'user-5');
      expect(json['joined_at'], isA<String>());
    });

    test('fromJson parses ISO date string', () {
      final json = {
        'id': 'member-6',
        'team_id': 'team-5',
        'user_id': 'user-6',
        'role': 'admin',
        'joined_at': '2026-05-06T10:30:00.000Z',
      };
      final member = TeamMember.fromJson(json);
      expect(member.joinedAt.year, 2026);
      expect(member.joinedAt.month, 5);
      expect(member.joinedAt.day, 6);
    });

    test('fromJson handles int milliseconds', () {
      final now = DateTime.now();
      final json = {
        'id': 'member-7',
        'team_id': 'team-6',
        'user_id': 'user-7',
        'role': 'member',
        'joined_at': now.millisecondsSinceEpoch,
      };
      final member = TeamMember.fromJson(json);
      expect(member.joinedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('Team fromJson parses ISO date string', () {
      final json = {
        'id': 'team-7',
        'name': 'Date Team',
        'invite_code': 'DATE123',
        'created_by': 'admin',
        'created_at': '2026-05-06T10:30:00.000Z',
      };
      final team = Team.fromJson(json);
      expect(team.createdAt.year, 2026);
      expect(team.createdAt.month, 5);
    });
  });
}
