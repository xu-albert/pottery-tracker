import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../features/auth/screens/device_locked_screen.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/shell/screens/shell_screen.dart';
import '../features/shell/screens/starting_screen.dart';
import '../features/album/screens/album_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/manage_clays_screen.dart';
import '../features/settings/screens/manage_glazes_screen.dart';
import '../features/settings/screens/manage_tags_screen.dart';
import '../features/create_piece/screens/create_piece_screen.dart';
import '../features/piece_detail/screens/piece_detail_screen.dart';
import '../features/piece_detail/screens/archived_piece_detail_screen.dart';
import '../features/feedback/screens/feedback_screen.dart';

/// How long the app takes to arrive behind the departing splash mark.
///
/// The splash lifts its mark away and only then releases the router, so without
/// a transition the app would snap in the instant the mark finished going.
const _appEntryDuration = Duration(milliseconds: 420);

/// How far the incoming page rises as it arrives, as a fraction of its height.
///
/// Opacity alone is not enough here: the app and the splash share the same cream
/// ground, so the low-opacity half of a fade is invisible and the page reads as
/// appearing suddenly in the last third of its own animation. A few pixels of
/// movement are far more legible than faint alpha on a matching background.
const _appEntryRise = 0.012;

/// Wraps [child] in a page that fades and rises into place.
CustomTransitionPage<T> _appEntry<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: _appEntryDuration,
    reverseTransitionDuration: _appEntryDuration,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, _appEntryRise),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  );
}

/// Hoisted so it survives `routerProvider` recomputing. `GoRouter` mints a
/// fresh `GoRouter` instance (and, without this, a fresh default
/// `GlobalKey<NavigatorState>`) every time `authProvider` or
/// `splashCompleteProvider` changes. A stable navigator key lets the
/// rebuilt router reuse the existing `Navigator` element instead of
/// remounting the whole subtree — otherwise in-flight state like the splash
/// screen's draw-on animation gets discarded and replayed from zero.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authProvider.select((s) => s.status));
  // A device holding another account's pottery is read-only, and the lock is
  // enforced here rather than screen by screen: no route that can write is
  // reachable while it holds.
  final deviceLocked = ref.watch(deviceLockedProvider);
  // Whether anyone already has a stake in what is on this device, which is
  // what decides whether the redirect may pass through while auth resolves.
  final deviceStamped = ref.watch(deviceStampedProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // While auth is resolving on a device nobody has claimed, the app simply
      // stays where it is: the splash overlay covers it and the album
      // underneath gets a head start on its query.
      //
      // On a claimed device it holds instead. The lock cannot answer yet — a
      // session-less state is both the owner offline and a refused account
      // relaunching — and passing through would mount the owner's album, and
      // leave it hit-testable under the overlay, on a device that may be
      // refused. The splash covers the holding route just the same.
      if (authStatus == AuthStatus.unknown) {
        if (!deviceStamped) return null;
        return loc == '/starting' ? null : '/starting';
      }
      if (loc == '/starting') return '/';

      final isSignedIn = authStatus == AuthStatus.authenticated;

      if (!isSignedIn && loc != '/sign-in') return '/sign-in';
      if (isSignedIn && loc == '/sign-in') return '/';

      if (deviceLocked && loc != '/device-locked') return '/device-locked';
      if (!deviceLocked && loc == '/device-locked') return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/starting',
        pageBuilder: (context, state) =>
            _appEntry(state, const StartingScreen()),
      ),
      GoRoute(
        path: '/device-locked',
        pageBuilder: (context, state) =>
            _appEntry(state, const DeviceLockedScreen()),
      ),
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) => _appEntry(state, const SignInScreen()),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) =>
            _appEntry(state, ShellScreen(navigationShell: navigationShell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const AlbumScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreatePieceScreen(),
      ),
      GoRoute(
        path: '/settings/clays',
        builder: (context, state) => const ManageClaysScreen(),
      ),
      GoRoute(
        path: '/settings/glazes',
        builder: (context, state) => const ManageGlazesScreen(),
      ),
      GoRoute(
        path: '/settings/tags',
        builder: (context, state) => const ManageTagsScreen(),
      ),
      GoRoute(
        path: '/piece/:id',
        builder: (context, state) {
          final pieceId = state.pathParameters['id']!;
          final isArchived = state.uri.queryParameters['archived'] == 'true';
          if (isArchived) {
            return ArchivedPieceDetailScreen(pieceId: pieceId);
          }
          return PieceDetailScreen(pieceId: pieceId);
        },
      ),
      GoRoute(
        path: '/feedback',
        builder: (context, state) => const FeedbackScreen(),
      ),
    ],
  );
});
