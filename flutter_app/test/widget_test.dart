import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/app.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';

void main() {
  testWidgets('App renders login screen when unauthenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider
              .overrideWith(() => _FakeAuthStateNotifier()),
        ],
        child: const App(),
      ),
    );

    expect(find.text('Sticker Swapp'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}

class _FakeAuthStateNotifier extends AuthStateNotifier {
  @override
  AppAuthState build() => const AuthUnauthenticated();
}
