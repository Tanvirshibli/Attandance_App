/// The app's permission vocabulary, mirroring what an HRM admin ticks in the
/// role editor on the HRM web client.
///
/// ## Why this is a table and not a constant per call site
///
/// The strings arrive from `pphl_erp` at runtime (`GET /api/v1/get-my-info` →
/// `user.permissions`) and are **data, not code**: the catalogue on the server
/// is created at runtime through `POST /api/v1/store/permission`, not by a
/// seeder, so it can grow without the app being rebuilt. Two rules follow, and
/// they are the whole reason this file exists:
///
///  * **An unrecognised string must never throw.** HRM adding a module must not
///    be able to crash an installed build. Unknown strings are simply ignored by
///    [PermissionService].
///  * **The module→permission mapping lives here and nowhere else**, so a
///    permission cannot be enforced in one screen and missed in another.
///
/// Grouping mirrors the HRM web client, which derives its own groups by
/// splitting each `module.action` name on the dot
/// (`PeoplesHRM_FontEnd/src/services/PermissionService.js:67`). The `liveBird*`
/// and `*Booking` entries below are carried for completeness — they come from
/// the same HRM list but have no screen in this app yet, so they gate nothing
/// today and start working the moment such a screen is added.
class AppPermissions {
  const AppPermissions._();

  // --- Payment receive info -------------------------------------------------
  static const String prInfoCreate = 'prInfo.create';
  static const String prInfoRead = 'prInfo.read';

  // --- Sales orders ---------------------------------------------------------
  static const String salesOrderCreate = 'salesOrder.create';
  static const String salesOrderRead = 'salesOrder.read';

  // --- Live bird orders -----------------------------------------------------
  static const String liveBirdOrderCreate = 'liveBirdOrder.create';
  static const String liveBirdOrderRead = 'liveBirdOrder.read';
  static const String liveBirdOrderAll = 'liveBirdOrder.all';
  static const String liveBirdOrderLive = 'liveBirdOrder.live';
  static const String liveBirdOrderCull = 'liveBirdOrder.cull';

  // --- Fertilizer orders ----------------------------------------------------
  static const String fertilizerOrderCreate = 'fertilizerOrder.create';
  static const String fertilizerOrderRead = 'fertilizerOrder.read';

  // --- Chicks bookings ------------------------------------------------------
  static const String chicksBookingCreate = 'chicksBooking.create';
  static const String chicksBookingRead = 'chicksBooking.read';

  // --- Feed bookings --------------------------------------------------------
  static const String feedBookingCreate = 'feedBooking.create';
  static const String feedBookingRead = 'feedBooking.read';

  // --- Dealers --------------------------------------------------------------
  static const String dealerCreate = 'dealer.create';
  static const String dealerRead = 'dealer.read';

  // --- Farms ----------------------------------------------------------------
  static const String farmsCreate = 'farms.create';
  static const String farmsRead = 'farms.read';

  // --- Markets --------------------------------------------------------------
  static const String marketsCreate = 'markets.create';
  static const String marketsRead = 'markets.read';

  // --- Vehicles -------------------------------------------------------------
  static const String vehiclesRead = 'vehicles.read';

  // --- Geo tracking ---------------------------------------------------------
  static const String trackingRead = 'tracking.read';

  // --- HR benefits ----------------------------------------------------------
  static const String benefitsRead = 'benefits.read';

  /// Every string this app understands, for diagnostics and tests. This is not
  /// a whitelist used for authorisation — the granted set comes from HRM and
  /// may legitimately contain strings absent here.
  static const List<String> all = <String>[
    prInfoCreate,
    prInfoRead,
    salesOrderCreate,
    salesOrderRead,
    liveBirdOrderCreate,
    liveBirdOrderRead,
    liveBirdOrderAll,
    liveBirdOrderLive,
    liveBirdOrderCull,
    fertilizerOrderCreate,
    fertilizerOrderRead,
    chicksBookingCreate,
    chicksBookingRead,
    feedBookingCreate,
    feedBookingRead,
    dealerCreate,
    dealerRead,
    farmsCreate,
    farmsRead,
    marketsCreate,
    marketsRead,
    vehiclesRead,
    trackingRead,
    benefitsRead,
  ];

  /// Permission required to *see* each app module at all.
  ///
  /// A module with no entry here is unconditional. `Farms & dealers` takes a
  /// list rather than a single string because its three tabs are separate
  /// records: an officer who may only read markets should still see the hub.
  static const Map<String, List<String>> moduleReadPermissions =
      <String, List<String>>{
    'benefits': <String>[benefitsRead],
    'vehicles': <String>[vehiclesRead],
    'tracking': <String>[trackingRead],
    'marketing': <String>[farmsRead, marketsRead, dealerRead],
  };

  /// Permission required to *create* within each app module.
  ///
  /// Missing a `*.create` does not hide the feature — the action stays visible
  /// and disabled with a reason, so the user can see it exists and ask for it.
  ///
  /// Keyed by the marketing tab's own key (`farm`, `dealer`, `market`), not by
  /// the permission's module name (`farms`). One key space, so a create gate
  /// can never silently miss: [marketingCreatePermission] takes the same key as
  /// [marketingReadPermissions] and the hub passes one string to all three.
  static const Map<String, String> moduleCreatePermissions = <String, String>{
    'farm': farmsCreate,
    'dealer': dealerCreate,
    'market': marketsCreate,
  };

  /// The permission required to create inside a marketing tab.
  static String? marketingCreatePermission(String tabKey) =>
      moduleCreatePermissions[tabKey];

  /// The read permissions gating a marketing tab's presence, or null when the
  /// tab is visible to everyone who reached the hub.
  static List<String>? marketingReadPermissions(String tabKey) {
    switch (tabKey) {
      case 'farm':
        return const <String>[farmsRead];
      case 'dealer':
        return const <String>[dealerRead];
      case 'market':
        return const <String>[marketsRead];
      default:
        return null;
    }
  }

  /// Human-readable subject for the "you do not have permission to…" message,
  /// so the wording a user reads matches the tab or module they are looking at.
  static String subjectFor(String moduleKey) {
    switch (moduleKey) {
      case 'benefits':
        return 'view HR benefits';
      case 'vehicles':
        return 'view vehicles';
      case 'tracking':
        return 'use geo tracking';
      case 'farm':
        return 'create farms';
      case 'dealer':
        return 'create dealers';
      case 'market':
        return 'create markets';
      default:
        return 'access this section';
    }
  }
}
