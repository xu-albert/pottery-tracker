import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/splash_provider.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/shell/screens/shell_screen.dart';
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
  final splashComplete = ref.watch(splashCompleteProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;

      if (authStatus == AuthStatus.unknown || !splashComplete) {
        if (loc != '/splash') return '/splash';
        return null;
      }

      final isSignedIn = authStatus == AuthStatus.authenticated;

      if (loc == '/splash') return isSignedIn ? '/' : '/sign-in';
      if (!isSignedIn && loc != '/sign-in') return '/sign-in';
      if (isSignedIn && loc == '/sign-in') return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
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
