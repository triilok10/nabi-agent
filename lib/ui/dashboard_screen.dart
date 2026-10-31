import 'package:flutter/material.dart';

class NabiDashboardMetric extends StatelessWidget {
  const NabiDashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      );
}

class NabiAutomationStatusCard extends StatelessWidget {
  const NabiAutomationStatusCard({
    required this.isScheduled,
    super.key,
  });

  final bool isScheduled;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(
            isScheduled ? Icons.schedule_outlined : Icons.pause_circle_outline,
            color: isScheduled ? Colors.greenAccent : null,
          ),
          title: const Text('System automation'),
          subtitle: Text(
            isScheduled
                ? 'Daily background archive preparation is scheduled with WorkManager.'
                : 'Background archive scheduling is unavailable.',
          ),
          trailing: Text(isScheduled ? 'Scheduled' : 'Unavailable'),
        ),
      );
}

class NabiCommandPanel extends StatelessWidget {
  const NabiCommandPanel({
    required this.controller,
    required this.isProcessing,
    required this.onSubmit,
    required this.onMicrophone,
    required this.onStorage,
    super.key,
  });

  final TextEditingController controller;
  final bool isProcessing;
  final VoidCallback onSubmit;
  final VoidCallback onMicrophone;
  final VoidCallback onStorage;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Local command',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: 'Try “Instagram open karo”',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.chat_bubble_outline),
                  suffixIcon: IconButton(
                    tooltip: 'Run command',
                    onPressed: isProcessing ? null : onSubmit,
                    icon: isProcessing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Commands are handled and logged on this device. Offline voice '
                'recognition will be added in Stage 3.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isProcessing ? null : onMicrophone,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('Microphone permission'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing ? null : onStorage,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Storage access'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
