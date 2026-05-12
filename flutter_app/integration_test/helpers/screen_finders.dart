import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reusable finders for integration tests, organized by screen.
///
/// Each finder targets the exact text rendered by the production widgets,
/// making tests resilient to layout changes while coupling to user-visible
/// strings (which would break the UX if changed accidentally).

// ── Login Screen ────────────────────────────────────────────────────────

final loginTitle = find.text('Sticker Swapp');
final continueAsGuest = find.text('Continue as Guest');
final signUpButton = find.widgetWithText(FilledButton, 'Sign Up');
final signInButton = find.widgetWithText(FilledButton, 'Sign In');
final signUpToggle = find.text('Need an account? Sign Up');
final signInToggle = find.text('Already have an account? Sign In');
final emailField = find.widgetWithText(TextFormField, 'Email');
final passwordField = find.widgetWithText(TextFormField, 'Password');
final displayNameField = find.widgetWithText(TextFormField, 'Display Name');

// ── Age Verification Screen ─────────────────────────────────────────────

final ageVerificationTitle = find.text("When's your birthday?");
final dateOfBirthField = find.text('Select date');
final ageContinueButton = find.widgetWithText(FilledButton, 'Continue');
final ageConfirmButton = find.text('Confirm');
final ageGoBackButton = find.text('Go Back');

// ── Guest Migration Screen ──────────────────────────────────────────────

final migrationTitle = find.text('Transfer Your Collection');
final transferButton = find.widgetWithText(FilledButton, 'Transfer Stickers');
final migrationSkipButton = find.text('Skip');
final migrationSuccessTitle = find.text('Transfer Complete');
final migrationContinueButton = find.widgetWithText(FilledButton, 'Continue');

// ── Parental Consent Screen ─────────────────────────────────────────────

final consentTitle = find.text('Parent or Guardian Approval');
final parentEmailField =
    find.widgetWithText(TextField, "Parent's email address");
final sendConsentButton =
    find.widgetWithText(FilledButton, 'Send Consent Request');
final waitingForApproval = find.text('Waiting for Approval');

// ── Matches Screen (Discovery) ──────────────────────────────────────────

final matchesAppBarTitle = find.text('Sticker Swapp');
final gettingLocation = find.text('Getting your location...');
final noTradersNearby = find.text('No Traders Nearby');
final wishlistAppBarTitle = find.text('My Wishlist');

// ── Match Celebration Overlay ───────────────────────────────────────────

final celebrationTitle = find.text("It's a Match!");
final openChatButton = find.text('Open Chat');
final keepSwipingButton = find.text('Keep Swiping');

// ── Match Screen (Trade Confirmation) ───────────────────────────────────

final matchScreenTitle = find.text('Trade Match');
final markAsDoneButton = find.widgetWithText(FilledButton, 'Mark as Done');
final waitingForPartner = find.text('Waiting for partner...');
final tradeComplete = find.text('Trade Complete!');
final tradingNotAvailable = find.text('Trading Not Available');

// ── Chat Screen ─────────────────────────────────────────────────────────

final chatScreenTitle = find.text('Trade Chat');
final chatInputField = find.widgetWithText(TextField, 'Type a message...');
final chatSendButton = find.byIcon(Icons.send);
final chatNotAvailable = find.text('Chat Not Available');

// ── Under-13 Wishlist View ──────────────────────────────────────────────

final shareWishlistButton = find.text('Share Wishlist');
final collectionComplete = find.text('Collection complete!');
