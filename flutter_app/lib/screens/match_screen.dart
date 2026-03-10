import 'package:flutter/material.dart';
import 'chat_screen.dart';

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

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(matchId: matchId),
              ),
            );

          },
        ),
      ),
    );
  }
}