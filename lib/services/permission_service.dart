import 'package:flutter/foundation.dart';

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
class PermissionService extends ChangeNotifier {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

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
  /// Cheap and synchronous — call it from wherever the profile arrives rather
  /// than adding a fetch of its own. Ignores a null profile, since a failed
  /// `get-my-info` must not be read as "revoke everything" mid-session.
  void update(AuthUserProfile? profile) {
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
    notifyListeners();
  }

  /// Drops all state on logout, so a second user signing in on the same device
  /// never sees the previous user's grants — and so the window before their
  /// profile lands is closed rather than inheriting a stale list.
  void clear() {
    if (!_loaded && _granted.isEmpty && !_isAdmin && !_isSuperAdmin) {
      return;
    }
    _granted = const <String>{};
    _isAdmin = false;
    _isSuperAdmin = false;
    _loaded = false;
    notifyListeners();
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
