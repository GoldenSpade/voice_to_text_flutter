import 'package:flutter/material.dart';

class AppButtonTheme {
  final String nameKey;
  final Color appBarColor;
  final Color backgroundColor;
  final List<Color> colors;

  const AppButtonTheme({
    required this.nameKey,
    required this.appBarColor,
    required this.backgroundColor,
    required this.colors,
  });
}

const kAppThemes = <AppButtonTheme>[
  // 1 — Pastel
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
  // 2 — Vivid
  AppButtonTheme(
    nameKey: 'themeVivid',
    appBarColor: Color(0xFF1E0840),
    backgroundColor: Color(0xFF0D0820),
    colors: [
      Color(0xFFC040A0),
      Color(0xFFB8385A),
      Color(0xFF883860),
      Color(0xFF3C3C90),
      Color(0xFF5C3888),
    ],
  ),
  // 3 — Ocean (dark)
  AppButtonTheme(
    nameKey: 'themeOcean',
    appBarColor: Color(0xFF073B52),
    backgroundColor: Color(0xFF041E2C),
    colors: [
      Color(0xFF0E6B8B),
      Color(0xFF0B7272),
      Color(0xFF125E80),
      Color(0xFF0E5070),
      Color(0xFF0A4460),
    ],
  ),
  // 4 — Sunset (dark)
  AppButtonTheme(
    nameKey: 'themeSunset',
    appBarColor: Color(0xFF5C2A00),
    backgroundColor: Color(0xFF1E0D00),
    colors: [
      Color(0xFF8C4420),
      Color(0xFFA84A28),
      Color(0xFF7A3818),
      Color(0xFF904A18),
      Color(0xFF6A3010),
    ],
  ),
  // 5 — Mint (light)
  AppButtonTheme(
    nameKey: 'themeMint',
    appBarColor: Color(0xFF2E7D5A),
    backgroundColor: Color(0xFFE8F5EF),
    colors: [
      Color(0xFF2D6B4F),
      Color(0xFF27805A),
      Color(0xFF1F7060),
      Color(0xFF357848),
      Color(0xFF286055),
    ],
  ),
  // 6 — Lavender (light)
  AppButtonTheme(
    nameKey: 'themeLavender',
    appBarColor: Color(0xFF5A3A8B),
    backgroundColor: Color(0xFFF0EAFF),
    colors: [
      Color(0xFF5A3A8B),
      Color(0xFF4A3870),
      Color(0xFF6A3880),
      Color(0xFF503888),
      Color(0xFF4A4080),
    ],
  ),
];
