import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter_app/features/auth/presentation/screens/age_verification_screen.dart';
import 'package:flutter_app/features/auth/presentation/screens/parental_consent_screen.dart';
import 'package:flutter_app/features/matching/presentation/screens/match_screen.dart';
import 'package:flutter_app/features/chat/presentation/screens/chat_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final isAgeVerified = ref.watch(ageVerifiedProvider) ?? false;
  final needsConsent = ref.watch(needsParentalConsentProvider);

  return GoRouter(
    initialLocation: '/matches',
    redirect: (context, state) {
      final isAuth = authState is AuthAuthenticated;
      final loc = state.matchedLocation;
      final isLoginRoute = loc == '/login';
      final isAgeVerificationRoute = loc == '/age-verification';
      final isConsentRoute = loc == '/parental-consent';

      // Not logged in → login screen
      if (!isAuth && !isLoginRoute) return '/login';

      // Logged in + on login → move to next required step
      if (isAuth && isLoginRoute) {
        if (!isAgeVerified) return '/age-verification';
        if (needsConsent) return '/parental-consent';
        return '/matches';
      }

      // Logged in + not verified + not on verification screen → verify
      if (isAuth && !isAgeVerified && !isAgeVerificationRoute) {
        return '/age-verification';
      }

      // Logged in + verified + on verification screen → move forward
      if (isAuth && isAgeVerified && isAgeVerificationRoute) {
        return needsConsent ? '/parental-consent' : '/matches';
      }

      // Logged in + verified + needs consent + not on consent screen → consent
      if (isAuth && isAgeVerified && needsConsent && !isConsentRoute) {
        return '/parental-consent';
      }

      // Logged in + verified + has consent (or 13+) + on consent screen → main app
      if (isAuth && isAgeVerified && !needsConsent && isConsentRoute) {
        return '/matches';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/age-verification',
        name: 'age-verification',
        builder: (context, state) => const AgeVerificationScreen(),
      ),
      GoRoute(
        path: '/parental-consent',
        name: 'parental-consent',
        builder: (context, state) => const ParentalConsentScreen(),
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
