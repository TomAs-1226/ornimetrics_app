import 'dart:async';

class AiMessage {
  final String role; // user or ai
  final String content;
  AiMessage(this.role, this.content);
}

abstract class AiProvider {
  Future<AiMessage> send(List<AiMessage> history, {Map<String, dynamic>? context});
}

class MockAiProvider implements AiProvider {
  @override
  Future<AiMessage> send(List<AiMessage> history, {Map<String, dynamic>? context}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final topic = context != null && context.isNotEmpty
        ? 'Considering weather ${context['weather'] ?? ''} and feeder status ${context['sensors'] ?? ''}'
        : 'Here\'s a general thought';
    return AiMessage('ai',
        '$topic, try offering fresh seed, observe calmly, and log any behavior changes. (Mock AI response)');
  }
}

/// Placeholder for a real AI provider. Wire up your HTTPS endpoint or Cloud Function here.
class RealAiProvider implements AiProvider {
  RealAiProvider({this.endpoint, this.apiKey});
  final String? endpoint;
  final String? apiKey;

  @override
  Future<AiMessage> send(List<AiMessage> history, {Map<String, dynamic>? context}) async {
    throw UnimplementedError('Connect RealAiProvider to your backend (endpoint + apiKey).');
  }
}
