import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/matching/presentation/screens/match_screen.dart';
import 'package:flutter_app/features/chat/presentation/screens/chat_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/matches',
    routes: [
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
