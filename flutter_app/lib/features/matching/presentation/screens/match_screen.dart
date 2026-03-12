import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MatchScreen extends StatelessWidget {

  final String matchId;

  const MatchScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Trade Match")),
      body: Center(
        child: ElevatedButton(
          child: const Text("Open Chat"),
          onPressed: () {
            context.goNamed('chat', pathParameters: {'matchId': matchId});
          },
        ),
      ),
    );
  }
}