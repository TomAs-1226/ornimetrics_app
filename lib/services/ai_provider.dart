import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AiMessage {
  final String role; // user or ai
  final String content;
  AiMessage(this.role, this.content);
}

abstract class AiProvider {
  Future<AiMessage> send(
    List<AiMessage> history, {
    Map<String, dynamic>? context,
    String? modelOverride,
  });
}

class MockAiProvider implements AiProvider {
  @override
  Future<AiMessage> send(
    List<AiMessage> history, {
    Map<String, dynamic>? context,
    String? modelOverride,
  }) async {
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
  RealAiProvider({this.endpoint, this.apiKey, this.model});
  final String? endpoint;
  final String? apiKey;
  final String? model;

  @override
  Future<AiMessage> send(
    List<AiMessage> history, {
    Map<String, dynamic>? context,
    String? modelOverride,
  }) async {
    try {
      final uri = Uri.parse(endpoint ?? _openAiResponsesEndpoint);
      final chosenModel = modelOverride ?? model ?? _defaultModel;
      final key = apiKey ?? dotenv.env['OPENAI_API_KEY'];

      if (key == null || key.isEmpty) {
        return AiMessage('ai', 'AI key missing. Please set OPENAI_API_KEY in your .env file.');
      }

      final inputMessages = history
          .map((m) => {
                'role': m.role,
                'content': [
                  {'type': 'text', 'text': m.content}
                ]
              })
          .toList();

      final payload = {
        'model': chosenModel,
        'input': inputMessages,
        if (context != null && context.isNotEmpty) 'metadata': context,
      };

      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final output = json['output'] as List?;
        if (output != null && output.isNotEmpty) {
          final first = output.first;
          final content = (first is Map && first['content'] is List && (first['content'] as List).isNotEmpty)
              ? ((first['content'] as List).first['text'] ?? first['content'].first.toString()).toString()
              : first.toString();
          return AiMessage('ai', content);
        }
        final text = json['content']?.toString() ??
            json['message']?.toString() ??
            json['output_text']?.toString() ??
            'AI response unavailable';
        return AiMessage('ai', text);
      }

      // Graceful fallback to keep the chat usable if the endpoint is unreachable.
      String message = 'AI service unavailable (status ${resp.statusCode}).';
      try {
        final errJson = jsonDecode(resp.body);
        final errMsg = errJson['error']?['message']?.toString();
        if (errMsg != null && errMsg.isNotEmpty) {
          message = '$message $errMsg';
        }
      } catch (_) {}
      return AiMessage(
        'ai',
        '$message Ensure OPENAI_API_KEY is set in .env and the model name is valid.',
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

const String _openAiResponsesEndpoint = 'https://api.openai.com/v1/responses';
const String _defaultModel = 'gpt-4o';
