import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/search/search_results_screen.dart';
import '../../features/media_detail/media_detail_screen.dart';
import '../../features/download_manager/download_manager_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../shell/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) {
              final query = state.uri.queryParameters['q'] ?? '';
              return SearchResultsScreen(query: query);
            },
          ),
          GoRoute(
            path: '/media',
            builder: (context, state) {
              final url = state.uri.queryParameters['url'] ?? '';
              return MediaDetailScreen(url: url);
            },
          ),
          GoRoute(
            path: '/downloads',
            builder: (context, state) => const DownloadManagerScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});
