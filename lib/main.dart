import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/database/db_helper.dart';
import 'core/services/archival_worker.dart';
import 'core/services/call_assistant_service.dart';
import 'core/services/device_permission_service.dart';
import 'core/services/local_model_bridge.dart';
import 'core/services/nabi_action_handler.dart';
import 'core/services/nabi_speech_service.dart';
import 'ui/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final modelFile = File(
    path.join(supportDirectory.path, 'models', 'nabi-model.gguf'),
  );
  await DBHelper.instance.database;
  final callAssistantPreference = await DBHelper.instance.readUserPreference(
    'call_assistant_enabled',
  );
  final callAssistantEnabled = callAssistantPreference == true;
  await Workmanager().initialize(archivalCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    archivalTaskName,
    archivalTaskName,
    frequency: const Duration(hours: 24),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => CallAssistantService(initialValue: callAssistantEnabled),
      child: NabiApp(automationScheduled: true, modelPath: modelFile.path),
    ),
  );
}

class NabiApp extends StatelessWidget {
  const NabiApp({
    required this.automationScheduled,
    required this.modelPath,
    super.key,
  });

  final bool automationScheduled;
  final String modelPath;

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
    home: NabiHomePage(
      automationScheduled: automationScheduled,
      modelPath: modelPath,
    ),
  );
}

class NabiHomePage extends StatefulWidget {
  const NabiHomePage({
    required this.automationScheduled,
    required this.modelPath,
    super.key,
  });

  final bool automationScheduled;
  final String modelPath;

  @override
  State<NabiHomePage> createState() => _NabiHomePageState();
}

class _NabiHomePageState extends State<NabiHomePage>
    with WidgetsBindingObserver {
  int? _activeCalls;
  int? _activeRecords;
  bool _loadingArchive = false;
  bool _processingCommand = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _modelLoading = true;
  bool _importingModel = false;
  String? _memoryError;
  String? _modelError;
  LocalModelIntegrationBridge? _localModel;
  final TextEditingController _commandController = TextEditingController();
  final NabiSpeechService _speech = NabiSpeechService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMemoryStatus();
    _loadModel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commandController.dispose();
    unawaited(_speech.dispose());
    final model = _localModel;
    if (model != null) unawaited(model.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _isRecording) {
      setState(() => _isRecording = false);
      unawaited(_speech.cancelRecording());
    }
  }

  Future<void> _loadModel() async {
    try {
      if (!await File(widget.modelPath).exists()) {
        throw StateError('Add a local GGUF model at ${widget.modelPath}.');
      }
      final model = await LocalModelIntegrationBridge.load(
        modelPath: widget.modelPath,
      );
      if (!mounted) {
        unawaited(model.dispose());
        return;
      }
      setState(() {
        _localModel = model;
        _modelError = null;
        _modelLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _modelError = 'Could not load local model: $error';
          _modelLoading = false;
        });
      }
    }
  }

  Future<void> _loadMemoryStatus() async {
    try {
      final counts = await DBHelper.instance.activeRecordCounts();
      if (mounted) {
        setState(() {
          _memoryError = null;
          _activeCalls =
              (counts['call_assistant_logs'] ?? 0) +
              (counts['system_action_logs'] ?? 0) +
              (counts['memory_logs'] ?? 0);
          _activeRecords = counts.values.fold<int>(
            0,
            (sum, count) => sum + count,
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _memoryError = 'Could not load local memory: $error');
      }
    }
  }

  Future<void> _runCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty || _processingCommand) return;

    setState(() => _processingCommand = true);
    try {
      final result = await NabiActionHandler(
        model: _localModel,
        modelUnavailableReason: _modelError,
      ).handleCommand(command);
      if (!mounted) return;
      _commandController.clear();
      await _loadMemoryStatus();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.response)));
        try {
          await _speech.speak(result.response);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not speak the response: $error')),
            );
          }
        }
      }
    } catch (error) {
      if (mounted) {
        await _loadMemoryStatus();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Command could not be processed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingCommand = false);
    }
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      final result = await DevicePermissionService()
          .requestMicrophonePermission();
      if (!mounted) return;
      final message = switch (result) {
        DevicePermissionResult.granted =>
          'Microphone permission granted. Audio is processed locally.',
        DevicePermissionResult.permanentlyDenied =>
          'Microphone access is blocked. Enable it in system settings.',
        DevicePermissionResult.restricted =>
          'Microphone access is restricted by this device.',
        DevicePermissionResult.denied => 'Microphone permission was denied.',
        DevicePermissionResult.notRequired =>
          'Microphone permission is not required on this platform.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: result == DevicePermissionResult.permanentlyDenied
              ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
              : null,
        ),
      );
      if (result == DevicePermissionResult.granted ||
          result == DevicePermissionResult.notRequired) {
        await _speech.startRecording();
        if (mounted) setState(() => _isRecording = true);
      }
    } catch (error) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not request microphone access: $error'),
          ),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_processingCommand || _isTranscribing) return;
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });
      try {
        final transcript = await _speech.stopAndTranscribe();
        if (!mounted) return;
        _commandController.text = transcript;
        await _runCommand();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Offline transcription failed: $error')),
          );
        }
      } finally {
        if (mounted) setState(() => _isTranscribing = false);
      }
      return;
    }
    setState(() => _isTranscribing = true);
    try {
      await _requestMicrophonePermission();
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  Future<void> _requestStoragePermission() async {
    try {
      final result = await DevicePermissionService().requestStoragePermission();
      if (!mounted) return;
      final message = switch (result) {
        DevicePermissionResult.granted =>
          'Storage access granted for legacy Android storage.',
        DevicePermissionResult.permanentlyDenied =>
          'Storage access is blocked. Enable it in system settings.',
        DevicePermissionResult.restricted =>
          'Storage access is restricted by this device.',
        DevicePermissionResult.denied => 'Storage permission was denied.',
        DevicePermissionResult.notRequired =>
          'Android app-private storage needs no broad storage permission.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: result == DevicePermissionResult.permanentlyDenied
              ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
              : null,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check storage access: $error')),
        );
      }
    }
  }

  Future<void> _importModel() async {
    if (_importingModel || _modelLoading || _processingCommand) return;
    try {
      final selectedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      if (selectedFile == null || !mounted) return;
      if (!selectedFile.name.toLowerCase().endsWith('.gguf')) {
        throw const FormatException('Choose a GGUF model file.');
      }
      final selectedFileLength = await selectedFile.length();
      if (selectedFileLength == null || selectedFileLength <= 0) {
        throw const FormatException('The selected model file is empty.');
      }

      setState(() => _importingModel = true);
      await _installModelFile(selectedFile);
      await _loadModel();
      if (!mounted) return;
      final modelReady = _localModel != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            modelReady
                ? 'Local model imported and ready.'
                : 'Model copied, but it could not be loaded: $_modelError',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import local model: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importingModel = false);
    }
  }

  Future<void> _installModelFile(PlatformFile selectedFile) async {
    final modelFile = File(widget.modelPath);
    await modelFile.parent.create(recursive: true);

    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final temporaryFile = File('${widget.modelPath}.$suffix.tmp');
    final backupFile = File('${widget.modelPath}.$suffix.backup');
    final input = selectedFile.readAsByteStream().cast<List<int>>();
    var destinationBackedUp = false;
    var modelReloadRequired = false;

    try {
      await input.pipe(temporaryFile.openWrite());
      if (await temporaryFile.length() == 0) {
        throw const FormatException('The selected model file is empty.');
      }

      final previousModel = _localModel;
      if (previousModel != null) {
        await previousModel.dispose();
      }
      if (mounted) {
        setState(() {
          _localModel = null;
          _modelError = null;
          _modelLoading = true;
        });
        modelReloadRequired = true;
      }

      if (await modelFile.exists()) {
        await modelFile.rename(backupFile.path);
        destinationBackedUp = true;
      }
      await temporaryFile.rename(modelFile.path);
      if (destinationBackedUp) await backupFile.delete();
    } catch (_) {
      if (destinationBackedUp && !await modelFile.exists()) {
        await backupFile.rename(modelFile.path);
      }
      if (modelReloadRequired && mounted) await _loadModel();
      rethrow;
    } finally {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      if (await backupFile.exists() && await modelFile.exists()) {
        await backupFile.delete();
      }
    }
  }

  Future<void> _setCallAssistantPreference(
    CallAssistantService service,
    bool enabled,
  ) async {
    if (!enabled) {
      await _saveCallAssistantPreference(service, false);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call assistant preference'),
        content: const Text(
          'This preference is saved locally and does not activate a call feature. '
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
    if (approved == true) await _saveCallAssistantPreference(service, true);
  }

  Future<void> _saveCallAssistantPreference(
    CallAssistantService service,
    bool enabled,
  ) async {
    try {
      await DBHelper.instance.saveUserPreference(
        'call_assistant_enabled',
        enabled,
      );
      service.setEnabled(enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save this preference locally: $error'),
          ),
        );
      }
    }
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
      final prettyJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(contents));
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
                          'call transcripts, commands, responses, and locations, '
                          'will be attached. '
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
          NabiDashboardMetric(
            label: 'Active local records',
            value: _memoryError != null
                ? '—'
                : (_activeRecords?.toString() ?? '…'),
            icon: Icons.storage_outlined,
          ),
          NabiDashboardMetric(
            label: 'Call / command logs',
            value: _memoryError != null
                ? '—'
                : (_activeCalls?.toString() ?? '…'),
            icon: Icons.receipt_long_outlined,
          ),
          if (_memoryError != null)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                ),
                title: const Text('Could not load local memory'),
                subtitle: Text(_memoryError!),
                trailing: IconButton(
                  tooltip: 'Retry',
                  onPressed: _loadMemoryStatus,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          NabiAutomationStatusCard(isScheduled: widget.automationScheduled),
          NabiModelStatusCard(
            isReady: _localModel != null,
            status: _modelLoading
                ? 'Loading the on-device GGUF model…'
                : (_modelError ??
                      'GGUF model loaded for private on-device inference.'),
            isImporting: _importingModel,
            canImport:
                !_modelLoading &&
                !_processingCommand &&
                !_isRecording &&
                !_isTranscribing,
            onImportModel: _importModel,
          ),
          NabiCommandPanel(
            controller: _commandController,
            isProcessing: _processingCommand || _isTranscribing,
            isRecording: _isRecording,
            onSubmit: _runCommand,
            onMicrophone: _toggleRecording,
            onStorage: _requestStoragePermission,
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: callAssistant.isEnabled,
              onChanged: (value) =>
                  _setCallAssistantPreference(callAssistant, value),
              title: const Text('Call assistant'),
              subtitle: const Text(
                'Saved on this device only; no call controls or call-audio capture are active.',
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
