import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
    try {
      final uri = Uri.parse(endpoint ?? _defaultEcologyInsightsEndpoint);
      final payload = {
        'messages': history.map((m) => {'role': m.role, 'content': m.content}).toList(),
        if (context != null) 'context': context,
      };

      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = (json['reply'] ?? json['content'] ?? json['message'] ?? 'AI response unavailable').toString();
        return AiMessage('ai', reply);
      }

      // Graceful fallback to keep the chat usable if the endpoint is unreachable.
      return AiMessage(
        'ai',
        'AI service temporarily unavailable (status ${resp.statusCode}). Using cached guidance: '
            'Consider weather ${context?['weather'] ?? 'n/a'} and sensors ${context?['sensors'] ?? 'n/a'} before changing feeder behavior.',
      );
    } catch (e) {
      return AiMessage(
        'ai',
        'AI service unreachable ($e). Considering weather ${context?['weather'] ?? 'n/a'} and sensors ${context?['sensors'] ?? 'n/a'}, '
            'keep feeders dry and clean for safety.',
      );
    }
  }
}

const String _defaultEcologyInsightsEndpoint = String.fromEnvironment(
  'ECOLOGY_INSIGHTS_API',
  defaultValue: 'https://ecology-insights.example.com/api/chat',
);
