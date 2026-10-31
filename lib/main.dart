import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/database/db_helper.dart';
import 'core/services/archival_worker.dart';
import 'core/services/call_assistant_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBHelper.instance.database;
  await Workmanager().initialize(archivalCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    archivalTaskName,
    archivalTaskName,
    frequency: const Duration(hours: 24),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.not_required),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => CallAssistantService(),
      child: const NabiApp(),
    ),
  );
}

class NabiApp extends StatelessWidget {
  const NabiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nabi',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B7CFF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF101018),
      useMaterial3: true,
    ),
    home: const NabiHomePage(),
  );
}

class NabiHomePage extends StatefulWidget {
  const NabiHomePage({super.key});

  @override
  State<NabiHomePage> createState() => _NabiHomePageState();
}

class _NabiHomePageState extends State<NabiHomePage> {
  int? _activeCalls;
  int? _activeRecords;
  bool _loadingArchive = false;
  String? _memoryError;

  @override
  void initState() {
    super.initState();
    _loadMemoryStatus();
  }

  Future<void> _loadMemoryStatus() async {
    try {
      final counts = await DBHelper.instance.activeRecordCounts();
      if (mounted) {
        setState(() {
          _memoryError = null;
          _activeCalls = counts['call_assistant_logs'] ?? 0;
          _activeRecords = counts.values.fold<int>(
            0,
            (sum, count) => sum + (count ?? 0),
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _memoryError = 'Could not load local memory: $error');
      }
    }
  }

  Future<void> _setCallAssistantPreference(
    CallAssistantService service,
    bool enabled,
  ) async {
    if (!enabled) {
      service.setEnabled(false);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call assistant preference'),
        content: const Text(
          'This session-only preference does not activate a call feature. '
          'This build cannot answer calls, record caller audio, or enable '
          'call-accessibility controls. No call data is collected by enabling it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save preference'),
          ),
        ],
      ),
    );
    if (approved == true) service.setEnabled(true);
  }

  Future<void> _reviewArchive() async {
    if (_loadingArchive) return;
    setState(() => _loadingArchive = true);
    try {
      final file = await ArchivalWorker.preparePendingArchive();
      if (!mounted) return;
      if (file == null || !await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No records are older than 30 days.')),
        );
        return;
      }

      final contents = await file.readAsString();
      final prettyJson = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(contents));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review private archive'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                prettyJson,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close — keep data local'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ArchivalWorker.confirmLocalArchive(
                    reviewedFile: file,
                    reviewedContent: prettyJson,
                  );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) await _loadMemoryStatus();
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not archive records: $error'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Approve local archive'),
            ),
            OutlinedButton(
              onPressed: () async {
                final sent = await _sendReviewedArchive(file, prettyJson);
                if (sent && context.mounted) Navigator.pop(context);
              },
              child: const Text('Review and send email…'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archive review failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingArchive = false);
    }
  }

  Future<bool> _sendReviewedArchive(
    File reviewedFile,
    String reviewedContent,
  ) async {
    final smtpHost = TextEditingController();
    final smtpPort = TextEditingController(text: '587');
    final username = TextEditingController();
    final password = TextEditingController();
    final fromAddress = TextEditingController();
    final recipientAddress = TextEditingController();
    try {
      final approval = await showDialog<_SmtpApproval>(
        context: context,
        builder: (dialogContext) {
          final formKey = GlobalKey<FormState>();
          var hasReviewedAndApproved = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Approve archive email'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'The complete reviewed JSON, including any stored '
                          'call transcripts and locations, will be attached. '
                          'Settings and credentials are used only for this send.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: smtpHost,
                          decoration: const InputDecoration(
                            labelText: 'SMTP host',
                          ),
                          validator: _requiredField,
                        ),
                        TextFormField(
                          controller: smtpPort,
                          decoration: const InputDecoration(
                            labelText: 'SMTP port',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final port = int.tryParse(value ?? '');
                            return port == null || port < 1 || port > 65535
                                ? 'Enter a port from 1 to 65535'
                                : null;
                          },
                        ),
                        TextFormField(
                          controller: username,
                          decoration: const InputDecoration(
                            labelText: 'SMTP username (optional)',
                          ),
                          autocorrect: false,
                        ),
                        TextFormField(
                          controller: password,
                          decoration: const InputDecoration(
                            labelText: 'SMTP password (optional)',
                          ),
                          obscureText: true,
                          autocorrect: false,
                        ),
                        TextFormField(
                          controller: fromAddress,
                          decoration: const InputDecoration(
                            labelText: 'From address',
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: _requiredField,
                        ),
                        TextFormField(
                          controller: recipientAddress,
                          decoration: const InputDecoration(
                            labelText: 'Recipient address',
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: _requiredField,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: hasReviewedAndApproved,
                          onChanged: (value) => setDialogState(
                            () => hasReviewedAndApproved = value ?? false,
                          ),
                          title: const Text(
                            'I reviewed the JSON and approve sending it to this recipient.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: hasReviewedAndApproved
                      ? () {
                          if (!formKey.currentState!.validate()) return;
                          Navigator.pop(
                            dialogContext,
                            _SmtpApproval(
                              host: smtpHost.text.trim(),
                              port: int.parse(smtpPort.text.trim()),
                              username: username.text.trim(),
                              password: password.text,
                              fromAddress: fromAddress.text.trim(),
                              recipientAddress: recipientAddress.text.trim(),
                            ),
                          );
                        }
                      : null,
                  child: const Text('Send approved archive'),
                ),
              ],
            ),
          );
        },
      );
      if (approval == null) return false;

      await ArchivalWorker.sendUserApprovedArchive(
        reviewedFile: reviewedFile,
        reviewedContent: reviewedContent,
        userApproved: true,
        smtpHost: approval.host,
        smtpPort: approval.port,
        username: approval.username,
        password: approval.password,
        fromAddress: approval.fromAddress,
        recipientAddress: approval.recipientAddress,
      );
      if (mounted) {
        await _loadMemoryStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Approved archive email sent.')),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Archive email failed: $error')));
      }
      return false;
    } finally {
      smtpHost.dispose();
      smtpPort.dispose();
      username.dispose();
      password.dispose();
      fromAddress.dispose();
      recipientAddress.dispose();
    }
  }

  String? _requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final callAssistant = context.watch<CallAssistantService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nabi'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.offline_bolt_outlined,
                color: Colors.greenAccent,
              ),
              title: const Text('Local-first mode'),
              subtitle: const Text(
                'Memory stays on this device unless you approve an archive email.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Local memory'),
              subtitle: Text(
                _memoryError ??
                    (_activeRecords == null
                        ? 'Loading local record count…'
                        : '$_activeRecords active records stored on this device'
                              '${_activeCalls == null ? '' : ' ($_activeCalls call logs)'}'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: callAssistant.isEnabled,
              onChanged: (value) =>
                  _setCallAssistantPreference(callAssistant, value),
              title: const Text('Call assistant'),
              subtitle: const Text(
                'Session-only preference; this build has no call controls or call-audio capture.',
              ),
              secondary: const Icon(Icons.call_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Review 30-day archive'),
              subtitle: const Text(
                'Review records first, then choose local archival or an explicitly approved email.',
              ),
              trailing: _loadingArchive
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _loadingArchive ? null : _reviewArchive,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmtpApproval {
  const _SmtpApproval({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.fromAddress,
    required this.recipientAddress,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String fromAddress;
  final String recipientAddress;
}
