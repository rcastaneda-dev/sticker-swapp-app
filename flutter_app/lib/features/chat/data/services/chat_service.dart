import 'package:ably_flutter/ably_flutter.dart';

class ChatService {
  late Realtime _client;

  Future<void> connect() async {
    _client = Realtime(
      options: ClientOptions(
        authUrl: Uri.parse("http://localhost:8080/auth/ably-token").toString(),
        autoConnect: true,
      ),
    );
  }

  RealtimeChannel getMatchChannel(String matchId) {
    return _client.channels.get("match:$matchId");
  }

  Future<void> sendMessage(String matchId, String text) async {
    final channel = getMatchChannel(matchId);

    await channel.publish(
      name: "message",
      data: text,
    );
  }

  Stream<Message> subscribeToMessages(String matchId) {
    final channel = getMatchChannel(matchId);

    return channel.subscribe();
  }
}