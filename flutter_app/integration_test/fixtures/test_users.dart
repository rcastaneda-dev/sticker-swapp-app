// Factory functions for user metadata maps used in integration tests.

Map<String, dynamic> unverifiedMetadata({String name = 'TestUser'}) => {
      'display_name': name,
    };

Map<String, dynamic> adultVerifiedMetadata({String name = 'TestUser'}) => {
      'display_name': name,
      'age_verified_at': '2026-01-01T00:00:00Z',
      'is_under_13': false,
    };

Map<String, dynamic> under13VerifiedMetadata({String name = 'ChildUser'}) => {
      'display_name': name,
      'age_verified_at': '2026-01-01T00:00:00Z',
      'is_under_13': true,
    };

Map<String, dynamic> under13WithConsentMetadata({
  String name = 'ChildUser',
}) =>
    {
      'display_name': name,
      'age_verified_at': '2026-01-01T00:00:00Z',
      'is_under_13': true,
      'parental_consent_at': '2026-01-15T00:00:00Z',
      'parent_email': 'parent@example.com',
    };
