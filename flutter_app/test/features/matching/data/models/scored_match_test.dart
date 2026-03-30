import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/matching/data/models/scored_match.dart';

void main() {
  group('ScoredMatch', () {
    final json = <String, dynamic>{
      'user_id': 'abc-123',
      'display_name': 'Carlos Rivera',
      'distance_m': 1234.5,
      'duplicate_count': 42,
      'needed_count': 28,
      'they_have_i_need': 15,
      'i_have_they_need': 8,
      'proximity_score': 0.75,
      'reciprocal_score': 0.65,
      'activity_score': 0.92,
      'total_score': 0.76,
    };

    test('fromJson parses all fields', () {
      final match = ScoredMatch.fromJson(json);

      expect(match.userId, 'abc-123');
      expect(match.displayName, 'Carlos Rivera');
      expect(match.distanceM, 1234.5);
      expect(match.duplicateCount, 42);
      expect(match.neededCount, 28);
      expect(match.theyHaveINeed, 15);
      expect(match.iHaveTheyNeed, 8);
      expect(match.proximityScore, 0.75);
      expect(match.reciprocalScore, 0.65);
      expect(match.activityScore, 0.92);
      expect(match.totalScore, 0.76);
    });

    test('fromJson handles int values for float fields', () {
      final intJson = Map<String, dynamic>.from(json);
      intJson['distance_m'] = 500;
      intJson['proximity_score'] = 1;
      intJson['total_score'] = 0;

      final match = ScoredMatch.fromJson(intJson);

      expect(match.distanceM, 500.0);
      expect(match.proximityScore, 1.0);
      expect(match.totalScore, 0.0);
    });

    test('formattedDistance returns km for distances >= 1000 m', () {
      final match = ScoredMatch.fromJson(json);
      expect(match.formattedDistance, '1.2 km');
    });

    test('formattedDistance returns m for distances < 1000 m', () {
      final closeJson = Map<String, dynamic>.from(json);
      closeJson['distance_m'] = 456.7;

      final match = ScoredMatch.fromJson(closeJson);
      expect(match.formattedDistance, '457 m');
    });

    test('formattedDistance at exactly 1000 m returns km', () {
      final boundaryJson = Map<String, dynamic>.from(json);
      boundaryJson['distance_m'] = 1000.0;

      final match = ScoredMatch.fromJson(boundaryJson);
      expect(match.formattedDistance, '1.0 km');
    });
  });
}
