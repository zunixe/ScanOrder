import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/models/team.dart';

void main() {
  group('Team', () {
    test('fromMap creates correct Team', () {
      final map = {
        'id': 'abc-123',
        'name': 'Tim Test',
        'invite_code': 'XYZ789',
        'created_by': 'user-1',
        'created_at': '2025-01-01T00:00:00.000Z',
      };
      final team = Team.fromMap(map);
      expect(team.id, 'abc-123');
      expect(team.name, 'Tim Test');
      expect(team.inviteCode, 'XYZ789');
      expect(team.createdBy, 'user-1');
      expect(team.createdAt, DateTime.parse('2025-01-01T00:00:00.000Z'));
    });

    test('toMap roundtrip', () {
      final team = Team(
        id: 'abc-123',
        name: 'Tim Test',
        inviteCode: 'XYZ789',
        createdBy: 'user-1',
        createdAt: DateTime(2025, 1, 1),
      );
      final map = team.toMap();
      expect(map['id'], 'abc-123');
      expect(map['name'], 'Tim Test');
      expect(map['invite_code'], 'XYZ789');
      expect(map['created_by'], 'user-1');
    });
  });

  group('TeamMember', () {
    test('fromMap creates correct TeamMember', () {
      final map = {
        'id': 'mem-1',
        'team_id': 'team-1',
        'user_id': 'user-1',
        'role': 'admin',
        'joined_at': '2025-01-01T00:00:00.000Z',
        'email': 'test@test.com',
      };
      final member = TeamMember.fromMap(map);
      expect(member.id, 'mem-1');
      expect(member.teamId, 'team-1');
      expect(member.userId, 'user-1');
      expect(member.role, 'admin');
      expect(member.email, 'test@test.com');
    });

    test('fromMap with null email', () {
      final map = {
        'id': 'mem-1',
        'team_id': 'team-1',
        'user_id': 'user-1',
        'role': 'member',
        'joined_at': '2025-01-01T00:00:00.000Z',
        'email': null,
      };
      final member = TeamMember.fromMap(map);
      expect(member.email, isNull);
      expect(member.role, 'member');
    });

    test('toMap roundtrip', () {
      final member = TeamMember(
        id: 'mem-1',
        teamId: 'team-1',
        userId: 'user-1',
        role: 'admin',
        joinedAt: DateTime(2025, 1, 1),
        email: 'test@test.com',
      );
      final map = member.toMap();
      expect(map['id'], 'mem-1');
      expect(map['team_id'], 'team-1');
      expect(map['user_id'], 'user-1');
      expect(map['role'], 'admin');
      expect(map['email'], 'test@test.com');
    });
  });
}
