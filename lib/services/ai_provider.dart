import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AiMessage {
  final String role; // user, ai, assistant, system, developer
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
    return AiMessage(
      'ai',
      '$topic, try offering fresh seed, observe calmly, and log any behavior changes. (Mock AI response)',
    );
  }
}

/// Real Responses API provider.
/// Uses: POST https://api.openai.com/v1/responses
class RealAiProvider implements AiProvider {
  RealAiProvider({this.endpoint, this.apiKey, this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String? endpoint;
  final String? apiKey;
  final String? model;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<AiMessage> send(
      List<AiMessage> history, {
        Map<String, dynamic>? context,
        String? modelOverride,
      }) async {
    final uri = Uri.parse(endpoint ?? _openAiResponsesEndpoint);
    final chosenModel = modelOverride ?? model ?? _defaultModel;
    final key = apiKey ?? dotenv.env['OPENAI_API_KEY'];

    if (key == null || key.isEmpty) {
      return AiMessage('ai', 'AI key missing. Please set OPENAI_API_KEY in your .env file.');
    }

    final instructions = _buildInstructions(history);
    final input = _buildInputItems(history);
    final metadata = _sanitizeMetadata(context);

    final payload = <String, dynamic>{
      'model': chosenModel,
      'input': input,
      'store': false,
      if (instructions != null && instructions.trim().isNotEmpty) 'instructions': instructions,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };

    try {
      final resp = await _client
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode(payload),
      )
          .timeout(_timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final text = _extractAssistantText(json);
        return AiMessage('ai', text ?? 'AI response unavailable.');
      }

      // Error path: try to surface the API error message.
      String message = 'AI service unavailable (status ${resp.statusCode}).';
      try {
        final errJson = jsonDecode(resp.body);

        // ✅ Dart-safe parsing (avoids ternary vs null-aware-index ambiguity)
        String? errMsg;
        if (errJson is Map) {
          final errorObj = errJson['error'];
          if (errorObj is Map) {
            errMsg = errorObj['message']?.toString();
          }
        }

        if (errMsg != null && errMsg.isNotEmpty) {
          message = '$message $errMsg';
        }
      } catch (_) {}

      return AiMessage(
        'ai',
        '$message Ensure OPENAI_API_KEY is set and the model name is valid.',
      );
    } on TimeoutException catch (_) {
      return AiMessage(
        'ai',
        'AI request timed out. Considering weather ${context?['weather'] ?? 'n/a'} and sensors ${context?['sensors'] ?? 'n/a'}, '
            'keep feeders dry and clean for safety.',
      );
    } catch (e) {
      return AiMessage(
        'ai',
        'AI service unreachable ($e). Considering weather ${context?['weather'] ?? 'n/a'} and sensors ${context?['sensors'] ?? 'n/a'}, '
            'keep feeders dry and clean for safety.',
      );
    }
  }

  /// If you create this provider long-lived, call dispose() when done.
  void dispose() {
    _client.close();
  }

  // ----- Helpers -----

  String _mapRole(String role) {
    if (role == 'ai') return 'assistant';
    if (role == 'assistant' || role == 'user' || role == 'system' || role == 'developer') return role;
    // Default unknown roles to user (safer than assistant).
    return 'user';
  }

  String? _buildInstructions(List<AiMessage> history) {
    final parts = <String>[];
    for (final m in history) {
      final r = _mapRole(m.role);
      if (r == 'system' || r == 'developer') {
        final trimmed = m.content.trim();
        if (trimmed.isNotEmpty) parts.add(trimmed);
      }
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  List<Map<String, dynamic>> _buildInputItems(List<AiMessage> history) {
    final items = <Map<String, dynamic>>[];
    for (final m in history) {
      final r = _mapRole(m.role);
      if (r == 'system' || r == 'developer') continue; // moved into instructions
      final text = m.content.trim();
      if (text.isEmpty) continue;

      items.add({'role': r, 'content': text});
    }
    return items;
  }

  Map<String, String>? _sanitizeMetadata(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) return null;

    final out = <String, String>{};
    for (final entry in context.entries) {
      if (out.length >= 16) break;
      final k = entry.key.toString();
      var v = entry.value == null ? '' : entry.value.toString();
      if (k.length > 64) continue;
      if (v.length > 512) v = v.substring(0, 512);
      out[k] = v;
    }
    return out.isEmpty ? null : out;
  }

  String? _extractAssistantText(Map<String, dynamic> json) {
    final output = json['output'];
    if (output is! List) return json['message']?.toString();

    final parts = <String>[];
    for (final item in output) {
      if (item is! Map) continue;
      if (item['type'] != 'message') continue;
      if (item['role'] != 'assistant') continue;

      final content = item['content'];
      if (content is List) {
        for (final block in content) {
          if (block is Map) {
            final type = block['type']?.toString();
            if (type == 'output_text') {
              final t = block['text']?.toString();
              if (t != null && t.trim().isNotEmpty) parts.add(t);
            }
          }
        }
      } else if (content != null) {
        final t = content.toString();
        if (t.trim().isNotEmpty) parts.add(t);
      }
    }

    if (parts.isNotEmpty) return parts.join('\n');

    final maybeText = json['output_text']?.toString() ?? json['content']?.toString();
    if (maybeText != null && maybeText.trim().isNotEmpty) return maybeText;

    return null;
  }
}

const String _openAiResponsesEndpoint = 'https://api.openai.com/v1/responses';
const String _defaultModel = 'gpt-4o';