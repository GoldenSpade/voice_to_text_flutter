import 'package:flutter/material.dart';

class AppButtonTheme {
  final String nameKey;
  final Color appBarColor;
  final Color backgroundColor;
  final List<Color> colors;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentColor;

  const AppButtonTheme({
    required this.nameKey,
    required this.appBarColor,
    required this.backgroundColor,
    required this.colors,
    this.textPrimary = Colors.white,
    this.textSecondary = const Color(0xFFA6A6A6),
    this.accentColor = Colors.white,
  });
}

// Order: Multi-pastel → Neutral pastel → Warm/cool pastel → Green/Purple dark
const kAppThemes = <AppButtonTheme>[
  // 0 — Pastel (original favourite)
  AppButtonTheme(
    nameKey: 'themePastel',
    appBarColor: Color(0xFF0F3460),
    backgroundColor: Color(0xFF1A1A2E),
    colors: [
      Color(0xFF3D5A80),
      Color(0xFF6B4E71),
      Color(0xFF2D6A4F),
      Color(0xFF8B4049),
      Color(0xFF7B5E3A),
    ],
  ),
  // 1 — Dusk (cool multi-pastel)
  AppButtonTheme(
    nameKey: 'themeDusk',
    appBarColor: Color(0xFF1A3040),
    backgroundColor: Color(0xFF0C1820),
    colors: [
      Color(0xFF2E5870),
      Color(0xFF2A5858),
      Color(0xFF3A4870),
      Color(0xFF4A4060),
      Color(0xFF2A5040),
    ],
  ),
  // 2 — Earth (warm earthy multi-pastel)
  AppButtonTheme(
    nameKey: 'themeEarth',
    appBarColor: Color(0xFF3A2818),
    backgroundColor: Color(0xFF1A1208),
    colors: [
      Color(0xFF6A4A28),
      Color(0xFF7A4A38),
      Color(0xFF5A5828),
      Color(0xFF6A3838),
      Color(0xFF5A4A30),
    ],
  ),
  // 3 — Mono (neutral pastel, very muted diverse hues)
  AppButtonTheme(
    nameKey: 'themeMono',
    appBarColor: Color(0xFF303040),
    backgroundColor: Color(0xFF181820),
    colors: [
      Color(0xFF506080),
      Color(0xFF604868),
      Color(0xFF486058),
      Color(0xFF70505A),
      Color(0xFF584830),
    ],
  ),
  // 4 — Mist (cool atmospheric pastel)
  AppButtonTheme(
    nameKey: 'themeMist',
    appBarColor: Color(0xFF1A3050),
    backgroundColor: Color(0xFF0A1828),
    colors: [
      Color(0xFF3A5878),
      Color(0xFF484870),
      Color(0xFF2A6068),
      Color(0xFF504860),
      Color(0xFF3A5068),
    ],
  ),
  // 5 — Ocean (deep blue-teal pastel)
  AppButtonTheme(
    nameKey: 'themeOcean',
    appBarColor: Color(0xFF083848),
    backgroundColor: Color(0xFF041820),
    colors: [
      Color(0xFF1A6878),
      Color(0xFF1A5880),
      Color(0xFF0A6868),
      Color(0xFF1A7060),
      Color(0xFF1A4870),
    ],
  ),
  // 6 — Sakura (rose pastel)
  AppButtonTheme(
    nameKey: 'themeSakura',
    appBarColor: Color(0xFF502030),
    backgroundColor: Color(0xFF1A0810),
    colors: [
      Color(0xFF6A3850),
      Color(0xFF703848),
      Color(0xFF683070),
      Color(0xFF784050),
      Color(0xFF583060),
    ],
  ),
  // 7 — Sunset (warm rust-amber pastel)
  AppButtonTheme(
    nameKey: 'themeSunset',
    appBarColor: Color(0xFF482010),
    backgroundColor: Color(0xFF180A00),
    colors: [
      Color(0xFF784028),
      Color(0xFF705030),
      Color(0xFF784A28),
      Color(0xFF683820),
      Color(0xFF785038),
    ],
  ),
  // 8 — Vivid (muted purple-magenta pastel)
  AppButtonTheme(
    nameKey: 'themeVivid',
    appBarColor: Color(0xFF280A48),
    backgroundColor: Color(0xFF100418),
    colors: [
      Color(0xFF7840A0),
      Color(0xFF703090),
      Color(0xFF602898),
      Color(0xFF883080),
      Color(0xFF703888),
    ],
  ),
  // 9 — Mint (dark green)
  AppButtonTheme(
    nameKey: 'themeMint',
    appBarColor: Color(0xFF1A5038),
    backgroundColor: Color(0xFF0A2018),
    colors: [
      Color(0xFF2D6B4F),
      Color(0xFF27805A),
      Color(0xFF1F7060),
      Color(0xFF357848),
      Color(0xFF286055),
    ],
  ),
  // 10 — Lavender (dark purple)
  AppButtonTheme(
    nameKey: 'themeLavender',
    appBarColor: Color(0xFF3A2068),
    backgroundColor: Color(0xFF140A28),
    colors: [
      Color(0xFF5A3A8B),
      Color(0xFF4A3870),
      Color(0xFF6A3880),
      Color(0xFF503888),
      Color(0xFF4A4080),
    ],
  ),
  // 11 — Binance (dark gray + gold)
  AppButtonTheme(
    nameKey: 'themeBinance',
    appBarColor: Color(0xFFB8940A),
    backgroundColor: Color(0xFF181A20),
    colors: [
      Color(0xFF2B3139),
      Color(0xFF252A33),
      Color(0xFF1E2329),
      Color(0xFF2E3948),
      Color(0xFF232A35),
    ],
    textPrimary: Color(0xFFEAECEF),
    textSecondary: Color(0xFF848E9C),
    accentColor: Color(0xFFF0B90B),
  ),
];
