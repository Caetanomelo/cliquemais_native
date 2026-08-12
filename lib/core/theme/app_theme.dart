import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette ported 1:1 from the web app's `:root` CSS custom properties
/// in index.html (--bg, --accent, --success/warning/error, --radius-*,
/// --font-sans: Inter) plus the dashboard-specific cyan glow tokens
/// (#00F2FE, rgba(20,27,41,.65) glass cards) so the native build matches
/// the web app's UX, not just an independently-designed approximation.
class AppTheme {
  // Kept for the (currently unused) light theme — not part of this pass.
  static const Color bg = Color(0xFFFDF8EC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFDDD0B0);
  static const Color textMain = Color(0xFF1A1F2E);
  static const Color textSub = Color(0xFF6B6A60);

  // --bg / --bg-dashboard
  static const Color bgDark = Color(0xFF010409);
  static const Color bgDashboard = Color(0xFF0B111E);
  // Solid stand-in for the dashboard's translucent glass cards
  // (rgba(20,27,41,.65) over --bg), since most call sites here don't
  // sit on a BackdropFilter yet.
  static const Color surfaceDark = Color(0xFF141B29);
  // rgba(0,242,254,.25) — cyan card border used throughout the dashboard.
  static const Color borderDark = Color(0x4000F2FE);
  // --text-primary / --text-muted
  static const Color textMainDark = Color(0xFFFFFFFF);
  static const Color textSubDark = Color(0xFF94A3B8);

  // --accent
  static const Color accent = Color(0xFF38BDF8);
  // Dashboard glow accent (#00F2FE) — brighter cyan used for active
  // states, progress fills and card borders.
  static const Color accentBright = Color(0xFF00F2FE);
  // --btn-primary-start — secondary blue for icon variety on cards.
  static const Color accent2 = Color(0xFF0EA5E9);
  // White text/icons on accent2 only reach 2.77:1 (fails WCAG AA's 4.5:1
  // for text / 3:1 for icons) — accent2 stays as-is for icon/text-on-navy
  // uses (6.8:1+ there), but solid button fills need this darker shade.
  static const Color buttonBg = Color(0xFF0369A1);
  // --success / --error / --warning (warning doubles as "gold" — the
  // web reuses amber #FBBF24 for streak/trophy toasts).
  static const Color green = Color(0xFF4ADE80);
  static const Color red = Color(0xFFF87171);
  static const Color gold = Color(0xFFFBBF24);

  static const Color navy = Color(0xFF0B111E);
  static const Color navyMid = Color(0xFF0D1A2E);
  static const Color navyDeep = Color(0xFF010409);
  static const Color topbar = Color(0xFF010409);
  static const Color navBorder = Color(0x4000F2FE);

  // --radius-card / --radius-btn / --radius-sm
  static const double radiusCard = 24;
  static const double radiusBtn = 50;
  static const double radiusSm = 12;

  // --btn-primary gradient (135deg, #0ea5e9 -> #2563eb), darkened from the
  // web's literal values to buttonBg -> #2563eb: white text/icons on the
  // original #0ea5e9 stop only hit 2.77:1, below WCAG AA.
  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [buttonBg, Color(0xFF2563EB)],
  );

  /// Glass-card look (blur is left to the caller via BackdropFilter;
  /// this supplies the matching fill/border/glow from the CSS).
  static BoxDecoration glassCard({double radius = radiusCard}) => BoxDecoration(
    color: const Color(0xA6141B29), // rgba(20,27,41,.65)
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderDark, width: 1),
    boxShadow: const [
      BoxShadow(color: Color(0x3300F2FE), blurRadius: 24),
      BoxShadow(color: Color(0x1400F2FE), blurRadius: 48),
    ],
  );

  static bool isDark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  static Color bgOf(BuildContext ctx) => isDark(ctx) ? bgDark : bg;
  static Color surfaceOf(BuildContext ctx) =>
      isDark(ctx) ? surfaceDark : surface;
  static Color borderOf(BuildContext ctx) => isDark(ctx) ? borderDark : border;
  static Color textOf(BuildContext ctx) =>
      isDark(ctx) ? textMainDark : textMain;
  static Color subOf(BuildContext ctx) => isDark(ctx) ? textSubDark : textSub;

  static ThemeData get dark {
    // ~100 call sites across the app hardcode `fontFamily: 'Sora'` on
    // TextStyle, but nothing ever called GoogleFonts.sora() to fetch and
    // register it — so Flutter silently fell back to the platform font
    // everywhere. Triggering the load here (theme is built once at
    // startup) registers 'Sora' under that exact family name, matching
    // every existing explicit `fontFamily: 'Sora'` usage.
    GoogleFonts.sora();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: textMainDark, displayColor: textMainDark),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: bgDark,
      ),
      scaffoldBackgroundColor: bgDark,
      appBarTheme: AppBarTheme(
        backgroundColor: topbar,
        foregroundColor: textMainDark,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: textMainDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusBtn),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          elevation: 0,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      dividerColor: borderDark,
      dividerTheme: const DividerThemeData(color: borderDark, thickness: 1),
    );
  }
}
