import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The app's design system.
///
/// Replaces the ad-hoc styling that was spread across the screens: one palette,
/// one type scale, one spacing rhythm, one elevation set, and one icon per
/// module so the same idea looks identical everywhere.
class AppColors {
  const AppColors._();

  // Brand — deep teal. A poultry/field-service field tool: calm, legible in
  // daylight, and not the default SaaS blue.
  static const Color primary = Color(0xFF0E7C6B);
  static const Color primaryDark = Color(0xFF076053);
  static const Color primaryLight = Color(0xFF7FD9C8);
  static const Color accent = Color(0xFFF5A524);
  static const Color secondary = Color(0xFF7C5CFF);

  // Module accents. Each service area owns a hue so the Services grid and every
  // downstream screen read as separate destinations.
  static const Color mAttendance = Color(0xFF2563EB);
  static const Color mLeave = Color(0xFFDB2777);
  static const Color mPayments = Color(0xFF059669);
  static const Color mHr = Color(0xFF7C5CFF);
  static const Color mSales = Color(0xFFEA580C);
  static const Color mVehicles = Color(0xFF0891B2);
  static const Color mFarms = Color(0xFF65A30D);

  // Deliberately a deeper, darker rose than mLeave so the two pink modules
  // stay distinguishable on the Services grid.
  static const Color mGeo = Color(0xFFBE123C);

  // Status. Values unchanged from the previous theme so the handful of screens
  // not yet migrated keep the same semantics.
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF1744);
  static const Color info = Color(0xFF2979FF);

  // Surfaces
  static const Color canvas = Color(0xFFF2F6F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSunk = Color(0xFFE9F0EE);

  // Ink
  static const Color ink = Color(0xFF0F1A17);
  static const Color inkMuted = Color(0xFF52645F);
  static const Color inkFaint = Color(0xFF869691);
  static const Color line = Color(0xFFDCE7E3);
  static const Color shadow = Color(0x140F1A17);

  // Dark surfaces — check-in and face registration run camera-first, so they
  // stay dark. These replace three hardcoded hex literals.
  static const Color darkCanvas = Color(0xFF0A0E21);
  static const Color darkSurface = Color(0xFF141A2E);

  /// Header gradient: teal into a deeper teal.
  ///
  /// An earlier draft ran teal into violet, but on a real screen that read as
  /// two competing brands and fought the primary action button underneath it.
  /// Staying in one hue family keeps the header as chrome rather than a focal
  /// point, and leaves the accent colour free to mean "act here".
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F8C7C), Color(0xFF075048)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkCanvas, Color(0xFF16213E)],
  );

  /// Success gradient, used by the payslip net banner and checked-in states.
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [success, primary],
  );

  /// Single source of truth for status -> colour. Never used as the only
  /// signal: every caller pairs it with an icon and a word.
  static Color forStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'present':
      case 'active':
      case 'approved':
      case 'delivered':
      case 'completed':
        return success;
      case 'late':
      case 'requested':
      case 'pending':
      case 'in_transit':
      case 'intransit':
        return warning;
      case 'absent':
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return error;
      case 'leave':
        return info;
      case 'inactive':
      case 'archived':
      case 'draft':
        return inkFaint;
      default:
        return inkMuted;
    }
  }
}

class AppType {
  const AppType._();

  static TextStyle _pop({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle get display => _pop(size: 32, weight: FontWeight.w700);
  static TextStyle get h1 => _pop(size: 24, weight: FontWeight.w700);
  static TextStyle get h2 => _pop(size: 20, weight: FontWeight.w700);
  static TextStyle get h3 => _pop(size: 16, weight: FontWeight.w600);
  static TextStyle get title => _pop(size: 16, weight: FontWeight.w500);
  static TextStyle get body => _pop(size: 14, weight: FontWeight.w400);
  static TextStyle get bodyStrong =>
      _pop(size: 14, weight: FontWeight.w600);
  static TextStyle get bodySm => _pop(size: 13, weight: FontWeight.w400);
  static TextStyle get meta => _pop(size: 12, weight: FontWeight.w500);
  static TextStyle get micro => _pop(size: 11, weight: FontWeight.w500);

  /// Values that sit in a column and must line up.
  static TextStyle get numeric => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Light type on a dark camera surface reads optically thinner, so it gets
  /// a touch more line height and a heavier weight than the light-mode token.
  static TextStyle get onDark => _pop(
        size: 14,
        weight: FontWeight.w600,
        height: 1.35,
        letterSpacing: 0.1,
      );
}

class AppSpace {
  const AppSpace._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;

  /// The app-wide horizontal gutter. Every screen body lines up on this.
  static const double gutter = 20;

  /// Bottom clearance for the floating action button / bottom nav.
  static const double fabClearance = 100;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;
}

class AppShadows {
  const AppShadows._();

  static List<BoxShadow> get card => [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get raised => [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get floating => [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.14),
          blurRadius: 26,
          offset: const Offset(0, 10),
        ),
      ];
}

/// One icon per concept, app-wide. Using Phosphor here rather than inline
/// literals is what keeps a "vehicles" tile identical on the Services grid,
/// the vehicle hub and the trip list.
///
/// Every name below was verified to exist in phosphor_flutter 2.1.0. Duotone
/// icons must be rendered with [PhosphorIcon]; Flutter's plain `Icon`
/// silently degrades them to flat.
class AppIcons {
  const AppIcons._();

  // Bottom navigation
  static IconData get home => PhosphorIconsDuotone.house;
  static IconData get calendar => PhosphorIconsDuotone.calendarCheck;
  static IconData get bell => PhosphorIconsDuotone.bell;
  static IconData get user => PhosphorIconsDuotone.user;
  static IconData get grid => PhosphorIconsDuotone.squaresFour;

  // Modules
  static IconData get attendance => PhosphorIconsDuotone.sealCheck;
  static IconData get leave => PhosphorIconsDuotone.umbrella;
  static IconData get payments => PhosphorIconsDuotone.wallet;
  static IconData get hr => PhosphorIconsDuotone.gift;
  static IconData get sales => PhosphorIconsDuotone.chartLineUp;
  static IconData get vehicles => PhosphorIconsDuotone.truck;
  static IconData get farms => PhosphorIconsDuotone.plant;
  static IconData get geo => PhosphorIconsDuotone.mapPinLine;

  // Actions
  static IconData get camera => PhosphorIconsDuotone.camera;
  static IconData get face => PhosphorIconsDuotone.scan;
  static IconData get check => PhosphorIconsFill.checkCircle;
  static IconData get clock => PhosphorIconsDuotone.clock;
  static IconData get chart => PhosphorIconsDuotone.chartBar;
  static IconData get receipt => PhosphorIconsDuotone.receipt;
  static IconData get wallet => PhosphorIconsDuotone.wallet;
  static IconData get money => PhosphorIconsDuotone.bank;
  static IconData get piggy => PhosphorIconsDuotone.piggyBank;
  static IconData get fork => PhosphorIconsDuotone.forkKnife;
  static IconData get badge => PhosphorIconsDuotone.medal;
  static IconData get invoice => PhosphorIconsDuotone.fileText;
  static IconData get loan => PhosphorIconsDuotone.handshake;
  static IconData get route => PhosphorIconsDuotone.path;
  static IconData get wrench => PhosphorIconsDuotone.wrench;
  static IconData get fuel => PhosphorIconsDuotone.gasPump;
  static IconData get store => PhosphorIconsDuotone.storefront;
  static IconData get barn => PhosphorIconsDuotone.barn;
  static IconData get trend => PhosphorIconsDuotone.trendUp;
  static IconData get note => PhosphorIconsDuotone.notePencil;
  static IconData get filter => PhosphorIconsDuotone.funnel;
  static IconData get search => PhosphorIconsDuotone.magnifyingGlass;
  static IconData get back => PhosphorIconsDuotone.arrowLeft;
  static IconData get chevron => PhosphorIconsDuotone.caretRight;
  static IconData get refresh => PhosphorIconsDuotone.arrowClockwise;
  static IconData get power => PhosphorIconsDuotone.power;
  static IconData get lock => PhosphorIconsDuotone.lockKey;
  static IconData get shield => PhosphorIconsDuotone.shieldCheck;
  static IconData get info => PhosphorIconsDuotone.info;
  static IconData get error => PhosphorIconsDuotone.warningCircle;
  static IconData get warning => PhosphorIconsDuotone.warning;
  static IconData get plus => PhosphorIconsDuotone.plus;
  static IconData get trash => PhosphorIconsDuotone.trash;
  static IconData get edit => PhosphorIconsDuotone.pencilSimple;
  static IconData get image => PhosphorIconsDuotone.image;
  static IconData get upload => PhosphorIconsDuotone.uploadSimple;
  static IconData get download => PhosphorIconsDuotone.downloadSimple;
  static IconData get home2 => PhosphorIconsDuotone.houseLine;
  static IconData get sun => PhosphorIconsDuotone.sun;
  static IconData get qr => PhosphorIconsDuotone.qrCode;
  // No duotone weight ships for the lifebuoy, so this one stays flat.
  static IconData get help => PhosphorIconsRegular.lifebuoy;
  static IconData get pin => PhosphorIconsDuotone.mapPin;
  static IconData get target => PhosphorIconsDuotone.crosshair;
  static IconData get eye => PhosphorIconsDuotone.eye;
  static IconData get eyeOff => PhosphorIconsDuotone.eyeSlash;
  static IconData get inbox => PhosphorIconsDuotone.tray;
  static IconData get cloudOff => PhosphorIconsDuotone.cloudSlash;
  static IconData get megaphone => PhosphorIconsDuotone.megaphone;
  static IconData get question => PhosphorIconsDuotone.question;
  static IconData get translate => PhosphorIconsDuotone.translate;
  static IconData get moon => PhosphorIconsDuotone.moon;
  static IconData get key => PhosphorIconsDuotone.key;
}

/// Shared visual treatments used across several screens.
class AppDecorations {
  const AppDecorations._();

  /// A soft tinted wash behind a module accent, for icon tiles.
  static Color tint(Color color, [double alpha = 0.12]) =>
      color.withValues(alpha: alpha);

  static LinearGradient gradientFor(Color color) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color, Color.lerp(color, AppColors.secondary, 0.35)!],
      );
}
