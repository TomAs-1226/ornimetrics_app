import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/community_models.dart';
import '../services/ai_provider.dart';

class CommunityPostDetail extends StatefulWidget {
  const CommunityPostDetail({super.key, required this.post});
  final CommunityPost post;

  @override
  State<CommunityPostDetail> createState() => _CommunityPostDetailState();
}

class _CommunityPostDetailState extends State<CommunityPostDetail> {
  final _ai = MockAiProvider();
  final List<AiMessage> _messages = [AiMessage('ai', 'Ask me about this sighting. I consider weather + feeder state.')];
  final _controller = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _messages.add(AiMessage('user', _controller.text.trim()));
    });
    final contextMap = {
      'weather': widget.post.weather != null
          ? '${widget.post.weather!.temperatureC.toStringAsFixed(1)}C, ${widget.post.weather!.humidity.toStringAsFixed(0)}% humidity, ${widget.post.weather!.condition}'
          : 'No weather snapshot',
      'sensors': 'food low: ${widget.post.sensors.lowFood}, clogged: ${widget.post.sensors.clogged}, cleaning: ${widget.post.sensors.cleaningDue}',
      'model': widget.post.model,
      'tod': widget.post.timeOfDayTag,
      'caption': widget.post.caption,
    };
    final aiReply = await _ai.send(List.from(_messages), context: contextMap);
    setState(() {
      _messages.add(aiReply);
      _sending = false;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Scaffold(
      appBar: AppBar(title: const Text('Post details')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard(context, p),
                const SizedBox(height: 16),
                const Text('AI advice (mocked)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(m.content),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Ask AI about this post',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, CommunityPost p) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.author, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(DateFormat('MMM d, h:mm a').format(p.createdAt.toLocal()),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                Chip(label: Text(p.timeOfDayTag)),
              ],
            ),
            const SizedBox(height: 12),
            Text(p.caption, style: const TextStyle(fontSize: 16)),
            if (p.imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(p.imageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover),
              )
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(context, Icons.cloud_queue, p.weather != null
                    ? '${p.weather!.temperatureC.toStringAsFixed(1)}°C • ${p.weather!.humidity.toStringAsFixed(0)}%'
                    : 'Weather n/a'),
                _chip(context, Icons.info_outline, 'Model ${p.model}'),
                _chip(context, Icons.restaurant, p.sensors.lowFood ? 'Food low' : 'Food OK'),
                _chip(context, Icons.block, p.sensors.clogged ? 'Clogged?' : 'Flowing'),
                _chip(context, Icons.cleaning_services_outlined, p.sensors.cleaningDue ? 'Cleaning due' : 'Clean'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text('AI advice is informational; verify wildlife safety.',
                  style: Theme.of(context).textTheme.bodySmall),
            )
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
