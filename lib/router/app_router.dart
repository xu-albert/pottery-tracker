import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/shell/screens/shell_screen.dart';
import '../features/album/screens/album_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/manage_clays_screen.dart';
import '../features/settings/screens/manage_glazes_screen.dart';
import '../features/settings/screens/manage_tags_screen.dart';
import '../features/create_piece/screens/create_piece_screen.dart';
import '../features/piece_detail/screens/piece_detail_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isSignedIn = authState.status == AuthStatus.authenticated;
      final isSignInRoute = state.matchedLocation == '/sign-in';

      if (!isSignedIn && !isSignInRoute) return '/sign-in';
      if (isSignedIn && isSignInRoute) return '/';

      return null;
    },
    routes: [
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
                routes: [
                  GoRoute(
                    path: 'clays',
                    builder: (context, state) => const ManageClaysScreen(),
                  ),
                  GoRoute(
                    path: 'glazes',
                    builder: (context, state) => const ManageGlazesScreen(),
                  ),
                  GoRoute(
                    path: 'tags',
                    builder: (context, state) => const ManageTagsScreen(),
                  ),
                ],
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
        path: '/piece/:id',
        builder: (context, state) => PieceDetailScreen(
          pieceId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});
