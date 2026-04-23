import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authProvider.select((s) => s.status));

  return GoRouter(
    initialLocation: '/',
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;

      if (authStatus == AuthStatus.unknown) {
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
        builder: (context, state) => const SignInScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
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
    ],
  );
});
