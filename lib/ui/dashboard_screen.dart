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
      trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class NabiAutomationStatusCard extends StatelessWidget {
  const NabiAutomationStatusCard({required this.isScheduled, super.key});

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

class NabiModelStatusCard extends StatelessWidget {
  const NabiModelStatusCard({
    required this.isReady,
    required this.status,
    required this.isImporting,
    required this.canImport,
    required this.onImportModel,
    super.key,
  });

  final bool isReady;
  final String status;
  final bool isImporting;
  final bool canImport;
  final Future<void> Function() onImportModel;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        ListTile(
          leading: Icon(
            isReady ? Icons.memory_outlined : Icons.warning_amber_outlined,
            color: isReady ? Colors.greenAccent : Colors.orangeAccent,
          ),
          title: const Text('Local language model'),
          subtitle: Text(status),
          trailing: Text(isReady ? 'Ready' : 'Not ready'),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: canImport && !isImporting ? onImportModel : null,
              icon: isImporting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined),
              label: Text(
                isImporting
                    ? 'Importing model…'
                    : isReady
                    ? 'Replace model'
                    : 'Import model',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class NabiCommandPanel extends StatelessWidget {
  const NabiCommandPanel({
    required this.controller,
    required this.isProcessing,
    required this.isRecording,
    required this.onSubmit,
    required this.onMicrophone,
    required this.onStorage,
    super.key,
  });

  final TextEditingController controller;
  final bool isProcessing;
  final bool isRecording;
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
          Text('Local command', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Ask Nabi to do something…',
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
            'Commands, audio capture, speech recognition, and memory stay '
            'on this device. Voice only records while you hold an active session.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: isProcessing ? null : onMicrophone,
                icon: Icon(isRecording ? Icons.stop : Icons.mic_none),
                label: Text(isRecording ? 'Stop and transcribe' : 'Speak'),
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
