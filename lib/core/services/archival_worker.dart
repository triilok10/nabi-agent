import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../database/db_helper.dart';

const String archivalTaskName = 'nabi.prepare_reviewable_archive';

@pragma('vm:entry-point')
void archivalCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != archivalTaskName) return false;
    // The background task only prepares a local review file. It never emails
    // or deletes private records without an in-app user confirmation.
    await ArchivalWorker.preparePendingArchive();
    return true;
  });
}

class ArchivalWorker {
  ArchivalWorker._();

  static Future<File?> preparePendingArchive() async {
    final records = await DBHelper.instance.fetchExpiredRecords();
    final documents = await getApplicationDocumentsDirectory();
    final file = File(
      '${documents.path}${Platform.pathSeparator}pending_archive.json',
    );
    if (records.values.every((rows) => rows.isEmpty)) {
      if (await file.exists()) await file.delete();
      return null;
    }
    final payload = <String, Object>{
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'retention_days': DBHelper.retentionDays,
      'records': records,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  /// Confirms local archival after the user has reviewed the displayed JSON.
  ///
  /// Records are marked archived, not purged, so the active views no longer
  /// include them while their local data remains recoverable.
  static Future<void> confirmLocalArchive({
    required File reviewedFile,
    required String reviewedContent,
  }) async {
    final payload = jsonDecode(reviewedContent);
    final ids = _recordIdsFromPayload(payload);
    await DBHelper.instance.confirmArchivedRecords(ids);
    await _deleteIfUnchanged(reviewedFile, reviewedContent);
  }

  /// Sends only a file explicitly reviewed and approved in the foreground UI.
  ///
  /// Do not persist SMTP passwords in the app. A successful send marks the
  /// included rows archived; it does not purge their local copies.
  static Future<void> sendUserApprovedArchive({
    required File reviewedFile,
    required String reviewedContent,
    required bool userApproved,
    required String smtpHost,
    required int smtpPort,
    required String username,
    required String password,
    required String fromAddress,
    required String recipientAddress,
  }) async {
    if (!userApproved) {
      throw StateError('Explicit user approval is required before sending');
    }
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      throw const SocketException('No network connection is available');
    }
    final payload = jsonDecode(reviewedContent);
    final ids = _recordIdsFromPayload(payload);

    final mail = Message()
      ..from = Address(fromAddress)
      ..recipients.add(recipientAddress)
      ..subject = 'User-approved Nabi local archive'
      ..text = 'Attached is the archive you reviewed and approved for sending.'
      ..attachments.add(
        StreamAttachment(
          Stream<List<int>>.value(utf8.encode(reviewedContent)),
          'application/json',
          fileName: 'nabi-archive.json',
        ),
      );
    final smtp = SmtpServer(
      smtpHost,
      port: smtpPort,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      ssl: smtpPort == 465,
      allowInsecure: false,
    );
    await send(mail, smtp);
    await DBHelper.instance.confirmArchivedRecords(ids);
    await _deleteIfUnchanged(reviewedFile, reviewedContent);
  }

  static Future<void> _deleteIfUnchanged(
    File file,
    String reviewedContent,
  ) async {
    try {
      if (await file.exists() && await file.readAsString() == reviewedContent) {
        await file.delete();
      }
    } on FileSystemException {
      if (await file.exists()) rethrow;
    }
  }

  static Map<String, List<int>> _recordIdsFromPayload(Object? payload) {
    if (payload is! Map<String, dynamic> || payload['records'] is! Map) {
      throw const FormatException('Archive review file has an invalid format');
    }
    final records = payload['records'] as Map;
    final ids = <String, List<int>>{};
    for (final table in const [
      'call_assistant_logs',
      'location_tracking_logs',
      'system_action_logs',
      'memory_logs',
    ]) {
      final rows = records[table];
      if (table == 'memory_logs' && rows == null) {
        ids[table] = [];
        continue;
      }
      if (rows is! List) {
        throw FormatException('Archive is missing table $table');
      }
      ids[table] = rows.map((row) {
        if (row is! Map<String, dynamic> || row['id'] is! int) {
          throw FormatException('Archive contains an invalid row in $table');
        }
        return row['id'] as int;
      }).toList();
    }
    return ids;
  }
}
