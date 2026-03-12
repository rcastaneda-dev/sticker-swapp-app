import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter_app/features/matching/presentation/screens/match_screen.dart';
import 'package:flutter_app/features/chat/presentation/screens/chat_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/matches',
    redirect: (context, state) {
      final isAuth = authState is AuthAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isAuth && !isLoginRoute) return '/login';
      if (isAuth && isLoginRoute) return '/matches';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/matches',
        name: 'matches',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Matches')),
        ),
        routes: [
          GoRoute(
            path: ':matchId',
            name: 'match',
            builder: (context, state) {
              final matchId = state.pathParameters['matchId']!;
              return MatchScreen(matchId: matchId);
            },
            routes: [
              GoRoute(
                path: 'chat',
                name: 'chat',
                builder: (context, state) {
                  final matchId = state.pathParameters['matchId']!;
                  return ChatScreen(matchId: matchId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
