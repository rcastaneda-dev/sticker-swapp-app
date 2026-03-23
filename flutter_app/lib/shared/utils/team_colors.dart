import 'dart:ui';

/// National team primary + secondary colors for placeholder sticker images.
///
/// Colors are sourced from each federation's official kit palette.
/// The fallback uses the Swapp brand navy/gold when team is unknown or null.
abstract final class TeamColors {
  static const Map<String, (Color primary, Color secondary)> _colors = {
    // Hosts
    'USA': (Color(0xFF002868), Color(0xFFBF0A30)),
    'Mexico': (Color(0xFF006847), Color(0xFFCE1126)),
    'Canada': (Color(0xFFFF0000), Color(0xFFFFFFFF)),
    // South America
    'Argentina': (Color(0xFF75AADB), Color(0xFFFFFFFF)),
    'Brazil': (Color(0xFFCBDB2A), Color(0xFF1C3578)),
    'Uruguay': (Color(0xFF5CBFEB), Color(0xFFFFFFFF)),
    'Colombia': (Color(0xFFFCD116), Color(0xFF003893)),
    'Ecuador': (Color(0xFFFFD100), Color(0xFF034EA2)),
    'Paraguay': (Color(0xFFD52B1E), Color(0xFF0038A8)),
    // CONCACAF
    'Panama': (Color(0xFFD21034), Color(0xFF003DA5)),
    'Costa Rica': (Color(0xFFD21034), Color(0xFF002B7F)),
    'Jamaica': (Color(0xFF009B3A), Color(0xFFFED100)),
    'Trinidad and Tobago': (Color(0xFFD21034), Color(0xFF000000)),
    // Europe
    'Germany': (Color(0xFF000000), Color(0xFFFFFFFF)),
    'Spain': (Color(0xFFAA151B), Color(0xFFF1BF00)),
    'France': (Color(0xFF002395), Color(0xFFFFFFFF)),
    'England': (Color(0xFFFFFFFF), Color(0xFF002366)),
    'Italy': (Color(0xFF0066B2), Color(0xFFFFFFFF)),
    'Portugal': (Color(0xFF006600), Color(0xFFFF0000)),
    'Netherlands': (Color(0xFFFF6600), Color(0xFFFFFFFF)),
    'Belgium': (Color(0xFFD4213D), Color(0xFFFDDA24)),
    'Croatia': (Color(0xFFFF0000), Color(0xFFFFFFFF)),
    'Denmark': (Color(0xFFC60C30), Color(0xFFFFFFFF)),
    'Switzerland': (Color(0xFFFF0000), Color(0xFFFFFFFF)),
    'Austria': (Color(0xFFED2939), Color(0xFFFFFFFF)),
    'Turkey': (Color(0xFFE30A17), Color(0xFFFFFFFF)),
    'Ukraine': (Color(0xFF005BBB), Color(0xFFFFD500)),
    'Serbia': (Color(0xFFC6363C), Color(0xFF0C4076)),
    'Hungary': (Color(0xFFCD2A3E), Color(0xFF436F4D)),
    // Asia
    'Japan': (Color(0xFF002395), Color(0xFFFFFFFF)),
    'South Korea': (Color(0xFFCD2E3A), Color(0xFF003478)),
    'Australia': (Color(0xFFFBD85B), Color(0xFF003F2D)),
    'Saudi Arabia': (Color(0xFF006C35), Color(0xFFFFFFFF)),
    'Iran': (Color(0xFFFFFFFF), Color(0xFF239F40)),
    'Iraq': (Color(0xFF007A3D), Color(0xFFFFFFFF)),
    'Uzbekistan': (Color(0xFF0099CC), Color(0xFFFFFFFF)),
    'Qatar': (Color(0xFF8A1538), Color(0xFFFFFFFF)),
    'Indonesia': (Color(0xFFFF0000), Color(0xFFFFFFFF)),
    // Africa
    'Morocco': (Color(0xFFC1272D), Color(0xFF006233)),
    'Senegal': (Color(0xFF009639), Color(0xFFFDEF42)),
    'Nigeria': (Color(0xFF008751), Color(0xFFFFFFFF)),
    'Cameroon': (Color(0xFF007A5E), Color(0xFFFCD116)),
    'Egypt': (Color(0xFFCE1126), Color(0xFFFFFFFF)),
    'Ivory Coast': (Color(0xFFFF8200), Color(0xFF009E60)),
    'Algeria': (Color(0xFF006633), Color(0xFFFFFFFF)),
    'Mali': (Color(0xFF14B53A), Color(0xFFFCD116)),
    'Tunisia': (Color(0xFFE70013), Color(0xFFFFFFFF)),
    // Oceania
    'New Zealand': (Color(0xFF000000), Color(0xFFFFFFFF)),
  };

  /// Returns (primary, secondary) colors for a team.
  /// Falls back to Swapp brand navy/gold for unknown or null teams.
  static (Color, Color) forTeam(String? team) =>
      _colors[team] ?? const (Color(0xFF0A1F44), Color(0xFFC89B3C));
}
