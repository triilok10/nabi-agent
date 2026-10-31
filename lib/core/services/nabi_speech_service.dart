import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

class NabiSpeechService {
  NabiSpeechService({
    FlutterTts? engine,
    AudioRecorder? recorder,
    WhisperController? whisper,
  }) : _engine = engine ?? FlutterTts(),
       _recorder = recorder ?? AudioRecorder(),
       _whisper = whisper ?? WhisperController();

  final FlutterTts _engine;
  final AudioRecorder _recorder;
  final WhisperController _whisper;
  bool _initialized = false;
  bool _whisperInitialized = false;
  String? _recordingPath;

  bool get isRecording => _recordingPath != null;

  Future<void> startRecording() async {
    if (isRecording) throw StateError('Audio recording is already active.');
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted.');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final audioPath = path.join(
      temporaryDirectory.path,
      'nabi-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: audioPath,
    );
    _recordingPath = audioPath;
  }

  Future<String> stopAndTranscribe() async {
    final recordingPath = _recordingPath;
    if (recordingPath == null) {
      throw StateError('No microphone recording is active.');
    }
    final stoppedPath = await _recorder.stop();
    _recordingPath = null;
    if (stoppedPath == null || stoppedPath != recordingPath) {
      final audioFile = File(recordingPath);
      if (await audioFile.exists()) await audioFile.delete();
      throw StateError('The local audio recording was not saved correctly.');
    }

    final audioFile = File(stoppedPath);
    try {
      final model = WhisperModel.base;
      final modelPath = await _whisper.getPath(model);
      if (!await File(modelPath).exists()) {
        throw StateError(
          'Offline Whisper model is missing. Add ggml-${model.modelName}.bin '
          'to $modelPath.',
        );
      }
      _whisperInitialized = true;
      final result = await _whisper.transcribe(
        model: model,
        audioPath: stoppedPath,
        lang: 'auto',
        initialPrompt: 'हिंदी और English में बोले गए शब्दों को सही लिखें।',
        keepModelLoaded: true,
      );
      final transcript = result?.transcription.text.trim();
      if (transcript == null || transcript.isEmpty) {
        throw StateError('Whisper could not transcribe the local recording.');
      }
      return transcript;
    } finally {
      if (await audioFile.exists()) await audioFile.delete();
    }
  }

  Future<void> cancelRecording() async {
    final recordingPath = _recordingPath;
    if (recordingPath == null) return;
    _recordingPath = null;
    await _recorder.cancel();
    final audioFile = File(recordingPath);
    if (await audioFile.exists()) await audioFile.delete();
  }

  Future<void> speak(String text, {String language = 'hi-IN'}) async {
    final message = text.trim();
    if (message.isEmpty) return;
    if (!_initialized) {
      await _engine.setLanguage(language);
      await _engine.setSpeechRate(0.48);
      await _engine.setVolume(1);
      await _engine.setPitch(1);
      _initialized = true;
    }
    await _engine.stop();
    final result = await _engine.speak(message);
    if (result == 0) throw StateError('The device TTS engine could not speak.');
  }

  Future<void> stop() => _engine.stop();

  Future<void> dispose() async {
    await cancelRecording();
    await _recorder.dispose();
    await _engine.stop();
    if (_whisperInitialized) await _whisper.releaseModel();
  }
}
