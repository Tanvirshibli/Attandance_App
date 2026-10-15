import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_permissions.dart';
import '../models/auth_user_profile.dart';

/// Decides what the signed-in user may see and do, from the permission strings
/// HRM resolved for their roles.
///
/// ## Why this is a [ChangeNotifier] rather than a provider package
///
/// The app has no state-management dependency — no Provider, Riverpod, GetX or
/// Bloc — and every service is either an ad-hoc instance or a `static final`
/// singleton (`EndpointConfigService.instance`, `ZoneScopeService.instance`).
/// Adding a package for one boolean set would be the largest dependency change
/// in the repo. A [ChangeNotifier] plus [AnimatedBuilder] at the few call sites
/// that must react is enough, and matches `setState` in spirit.
///
/// ## Timing
///
/// Permissions arrive inside the `get-my-info` response, which
/// `AppBootstrap._warmAuthenticatedSession` already fetches **unawaited** so the
/// first frame is never blocked. This service is fed from that fetch, so it adds
/// no request and no latency — it simply fills in slightly after the shell
/// renders. Widgets watching it rebuild once.
///
/// ## Failing closed
///
/// Between the first frame and the profile landing, [isLoaded] is false. Gated
/// modules stay hidden in that window rather than appearing and then vanishing.
/// Ungated modules render immediately, so the services hub is never blank.
///
/// ## Background isolates
///
/// WorkManager and FCM start in fresh isolates where this service is empty, so
/// a gate there would deny for every user. [update] therefore mirrors the
/// decided state into a SharedPreferences snapshot that any isolate can
/// [hydrateFromStorage] without a profile fetch; a missing or unreadable
/// snapshot fails closed rather than guessing.
class PermissionService extends ChangeNotifier {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// Where the snapshot background isolates hydrate from lives; versioned so a
  /// future payload shape can ignore the old one.
  static const String _snapshotKey = 'permission_snapshot_v1';

  /// Granted permission names, lowercased. Comparisons are case-insensitive to
  /// match the HRM web client, which lowercases both sides
  /// (`PeoplesHRM_FontEnd/src/services/AuthorizationService.js` `canRender`).
  Set<String> _granted = const <String>{};

  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _loaded = false;

  /// True once a profile has supplied the permission list, successfully or not.
  /// A completed fetch with an empty list is a real answer — "this user has no
  /// permissions" — and must be treated differently from "we have not asked yet".
  bool get isLoaded => _loaded;

  /// The granted strings, lowercased. Exposed for diagnostics and the Profile
  /// screen; not a substitute for [can].
  Set<String> get granted => _granted;

  List<String> get grantedSorted => _granted.toList()..sort();

  bool get isAdmin => _isAdmin;
  bool get isSuperAdmin => _isSuperAdmin;

  /// Admins bypass every check, mirroring `AuthorizationService.canRender`,
  /// which returns true immediately for `isAdmin` or `isSuperAdmin`.
  bool get isAdminBypass => _isAdmin || _isSuperAdmin;

  /// Adopts the permissions carried by a freshly-fetched profile.
  ///
  /// Call it from wherever the profile arrives rather than adding a fetch of
  /// its own. Ignores a null profile, since a failed `get-my-info` must not be
  /// read as "revoke everything" mid-session.
  ///
  /// The new state applies to this isolate immediately; the snapshot background
  /// isolates hydrate from is written before listeners are notified, and a
  /// failed write is ignored — the in-memory state is already correct here.
  Future<void> update(AuthUserProfile? profile) async {
    if (profile == null) {
      return;
    }

    final granted = profile.permissions
        .map((permission) => permission.trim().toLowerCase())
        .where((permission) => permission.isNotEmpty)
        .toSet();

    final isAdmin = profile.isAdmin;
    final isSuperAdmin = profile.isSuperAdmin;

    final unchanged = _loaded &&
        granted.length == _granted.length &&
        granted.containsAll(_granted) &&
        isAdmin == _isAdmin &&
        isSuperAdmin == _isSuperAdmin;
    if (unchanged) {
      return;
    }

    _granted = granted;
    _isAdmin = isAdmin;
    _isSuperAdmin = isSuperAdmin;
    _loaded = true;

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _snapshotKey,
        jsonEncode(<String, Object>{
          'granted': _granted.toList(),
          'is_admin': _isAdmin,
          'is_super_admin': _isSuperAdmin,
        }),
      );
    } catch (_) {
      // Best-effort: the in-memory state is already correct for this isolate.
    }

    notifyListeners();
  }

  /// Drops all state on logout, so a second user signing in on the same device
  /// never sees the previous user's grants — and so the window before their
  /// profile lands is closed rather than inheriting a stale list. The snapshot
  /// goes with it, so a background isolate cannot hydrate the old grants.
  Future<void> clear() async {
    final hadState =
        _loaded || _granted.isNotEmpty || _isAdmin || _isSuperAdmin;
    _granted = const <String>{};
    _isAdmin = false;
    _isSuperAdmin = false;
    _loaded = false;

    // Removed even when this isolate held no state: a stale snapshot left by a
    // previous session must not stay hydratable by a background isolate after
    // logout.
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_snapshotKey);
    } catch (_) {
      // Best-effort: the next sign-in overwrites any snapshot left behind.
    }

    if (hadState) {
      notifyListeners();
    }
  }

  /// Loads the snapshot [update] persisted, for an isolate that started empty —
  /// the WorkManager worker or the FCM background handler.
  ///
  /// Returns false and leaves [isLoaded] false when there is no usable
  /// snapshot, so even a caller that ignores the result fails closed. Returns
  /// true immediately when this isolate already has state.
  Future<bool> hydrateFromStorage() async {
    if (_loaded) {
      return true;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_snapshotKey);
      if (raw == null || raw.isEmpty) {
        return false;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final rawGranted = decoded['granted'];
      if (rawGranted is! List) {
        return false;
      }

      _granted = rawGranted
          .whereType<String>()
          .map((permission) => permission.trim().toLowerCase())
          .where((permission) => permission.isNotEmpty)
          .toSet();
      _isAdmin = decoded['is_admin'] == true;
      _isSuperAdmin = decoded['is_super_admin'] == true;
      _loaded = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether [permission] is granted.
  ///
  /// A null or empty [permission] means "no requirement", so it is satisfied.
  /// An empty *granted* set is not the same thing and does not satisfy a named
  /// permission for a non-admin — see [isLoaded].
  bool can(String? permission) {
    if (permission == null || permission.isEmpty) {
      return true;
    }
    if (isAdminBypass) {
      return true;
    }
    return _granted.contains(permission.trim().toLowerCase());
  }

  /// Any-of: true when at least one of [permissions] is granted.
  ///
  /// An empty list means no requirement, so it is satisfied — matching
  /// `AuthorizationService.canRender`, whose loop simply never runs. This is the
  /// semantics a module tile uses, where holding any one of several permissions
  /// is enough to see the module.
  bool canAny(Iterable<String?>? permissions) {
    if (permissions == null) {
      return true;
    }
    final required = permissions.whereType<String>().where((p) => p.isNotEmpty);
    if (required.isEmpty) {
      return true;
    }
    if (isAdminBypass) {
      return true;
    }
    return required.any(can);
  }

  /// All-of: true only when every one of [permissions] is granted. Used where an
  /// action needs several grants at once.
  bool canAll(Iterable<String?> permissions) {
    final required = permissions.whereType<String>().where((p) => p.isNotEmpty);
    if (required.isEmpty) {
      return true;
    }
    if (isAdminBypass) {
      return true;
    }
    return required.every(can);
  }

  /// The read permissions gating [moduleKey], or null when the module is
  /// unconditional. See [AppPermissions.moduleReadPermissions].
  List<String>? readPermissionsFor(String moduleKey) =>
      AppPermissions.moduleReadPermissions[moduleKey];

  /// Whether the module is visible to the current user.
  ///
  /// A module absent from the catalogue is visible to everyone; that is the
  /// default for Attendance, Leave and Payments, which carry the employee's own
  /// records rather than an admin-managed module. A tile that forgot to declare
  /// its [moduleKey] therefore fails **open** — an ungated tile stays visible —
  /// which is the right default here: an app that silently swallows half its
  /// own menu would be worse than one that shows a module it should have
  /// hidden. The permission-bearing services enforce the same module again, so
  /// a missing key there fails closed.
  bool canViewModule(String? moduleKey) {
    if (moduleKey == null) {
      return true;
    }
    final required = readPermissionsFor(moduleKey);
    if (required == null) {
      return true;
    }
    return canAny(required);
  }

  /// Whether the user may create records inside [moduleKey].
  bool canCreateIn(String moduleKey) {
    final permission = AppPermissions.moduleCreatePermissions[moduleKey];
    if (permission == null) {
      return true;
    }
    return can(permission);
  }

  /// The message shown when an action is visible but not permitted. Phrased as a
  /// statement of fact with the route to fixing it, rather than a bare denial.
  String denialMessage(String moduleKey) =>
      'You do not have permission to '
      '${AppPermissions.subjectFor(moduleKey)}. '
      'Ask your HR admin to grant it.';
}
