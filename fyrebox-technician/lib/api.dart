import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

typedef Json = Map<String, dynamic>;
Json obj(dynamic v) => Map<String, dynamic>.from(v);
T clone<T>(T v) => jsonDecode(jsonEncode(v)) as T;
String newId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Native {
  static const ch = MethodChannel('fyrebox/native');
  static Future<String?> read(String m) async {
    try {
      return await ch.invokeMethod<String>(m);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> write(String m, String s) async {
    try {
      await ch.invokeMethod(m, s);
    } on MissingPluginException {
      /* Browser demonstration stays in memory. */
    }
  }

  static Future<Uint8List?> photo() => ch.invokeMethod<Uint8List>('takePhoto');
  static Future<String?> scan() => ch.invokeMethod<String>('scanQr');
  static Future<String> save(
    Uint8List bytes,
    String name, {
    bool share = false,
  }) async =>
      await ch.invokeMethod<String>('saveFile', {
        'bytes': bytes,
        'name': name,
        'share': share,
      }) ??
      'File ready.';
}

class AppApi {
  String endpoint = '', token = '';
  Json? user, db;
  final images = <String, Uint8List>{};
  bool get isDemo => endpoint.isEmpty;
  Future<void> init() async {
    final s = await Native.read('getSession');
    if (s != null && s.isNotEmpty) {
      try {
        final d = jsonDecode(s);
        endpoint = d['endpoint'] ?? '';
        token = d['token'] ?? '';
        user = d['user'];
        if (isDemo) await loadDemo();
      } catch (_) {
        user = null;
      }
    }
  }

  Future<void> loadDemo() async {
    if (db != null) return;
    final text = await Native.read('readWorkspace');
    try {
      if (text != null) db = obj(jsonDecode(text));
    } catch (_) {}
    db ??= obj(jsonDecode(await rootBundle.loadString('assets/demo.json')));
  }

  Future<void> persist() async =>
      Native.write('writeWorkspace', jsonEncode(db));
  Future<void> session() async => Native.write(
    'putSession',
    jsonEncode({'endpoint': endpoint, 'token': token, 'user': user}),
  );
  Future<void> loginDemo() async {
    endpoint = '';
    token = '';
    await loadDemo();
    user = obj(db!['user']);
    await session();
  }

  Future<void> login(String url, String email, String password) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      throw Exception('Enter a secure HTTPS workspace address.');
    endpoint = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!endpoint.endsWith('/api')) endpoint += '/api';
    token = '';
    final r = await call('auth/login', 'POST', {
      'email': email,
      'password': password,
    });
    token = r['token'];
    user = obj(r['user']);
    await session();
  }

  Future<void> logout() async {
    if (!isDemo) {
      try {
        await call('auth/logout', 'POST', {});
      } catch (_) {}
    }
    user = null;
    token = '';
    images.clear();
    await Native.write('putSession', '');
  }

  Future<dynamic> call(String path, [String method = 'GET', Json? body]) async {
    if (isDemo) {
      await loadDemo();
      return demoCall(path, method, body ?? {});
    }
    final client = http.Client();
    try {
      final req = http.Request(method, Uri.parse('$endpoint/$path'))
        ..headers.addAll({
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        });
      if (body != null) req.body = jsonEncode(body);
      final r = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 30)),
      ).timeout(const Duration(seconds: 30));
      dynamic d;
      try {
        d = jsonDecode(r.body);
      } catch (_) {
        throw Exception('The workspace returned an unreadable response.');
      }
      if (r.statusCode >= 400)
        throw Exception(d['message'] ?? 'The request could not be completed.');
      return d;
    } finally {
      client.close();
    }
  }

  Future<String> upload(
    Uint8List b,
    String site,
    String purpose, {
    String? inspectionId,
  }) async {
    if (isDemo) {
      final id = newId();
      db!['files'][id] = {'data': base64Encode(b), 'purpose': purpose};
      images[id] = b;
      await persist();
      return id;
    }
    final p = await call('files/prepare', 'POST', {
      'siteId': site,
      'purpose': purpose,
      'mimeType': purpose == 'signature' ? 'image/png' : 'image/jpeg',
      if (inspectionId != null) 'inspectionId': inspectionId,
    });
    final r = await http
        .put(
          Uri.parse(p['uploadUrl']),
          headers: Map<String, String>.from(p['headers']),
          body: b,
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode >= 400) throw Exception('Image upload failed.');
    await call('files/${p['id']}/complete', 'POST', {});
    images[p['id']] = b;
    return p['id'];
  }

  Future<Uint8List> image(String id) async {
    if (images.containsKey(id)) return images[id]!;
    if (isDemo) return images[id] = base64Decode(db!['files'][id]['data']);
    final p = await call('files/$id/url'),
        r = await http
            .get(Uri.parse(p['url']))
            .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Image unavailable.');
    return images[id] = r.bodyBytes;
  }

  Future<Uint8List> report(String id) async {
    if (isDemo) {
      final r = await call('inspections/$id');
      return makePdf(r['snapshot']);
    }
    for (var i = 0; i < 45; i++) {
      final j = await call('reports/$id');
      if (j['status'] == 'ready') {
        final r = await http.get(Uri.parse(j['downloadUrl']));
        if (r.statusCode != 200) throw Exception('Report download failed.');
        return r.bodyBytes;
      }
      if (j['status'] == 'failed')
        throw Exception('Report generation needs manager attention.');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('The report is still processing. Try again shortly.');
  }

  Future<Uint8List> qrPdf(Json a) async {
    final doc = pw.Document();
    final font = pw.Font.ttf(await rootBundle.load('assets/Montserrat.ttf'));
    final logo = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    String shortLabel(dynamic value) {
      final text = (value ?? '').toString();
      return text.length > 60 ? '${text.substring(0, 57)}...' : text;
    }
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(298, 420),
      margin: const pw.EdgeInsets.all(24),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => pw.Center(child: pw.SizedBox(width: 250, child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Image(logo, width: 115, height: 44),
          pw.SizedBox(height: 12),
          pw.Container(color: PdfColors.white, padding: const pw.EdgeInsets.all(20), child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(), data: a['qr_token'], width: 175, height: 175,
          )),
          pw.SizedBox(height: 10),
          pw.Text(a['code'], style: const pw.TextStyle(fontSize: 11)),
          pw.Text(shortLabel(a['name']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(shortLabel(a['site_name']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
        ],
      ))),
    ));
    return doc.save();
  }

  Future<Uint8List> makePdf(Json s) async {
    final doc = pw.Document(),
        font = pw.Font.ttf(await rootBundle.load('assets/Montserrat.ttf')),
        logo = pw.MemoryImage(
          (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
        );
    final photos = <pw.Widget>[];
    for (final f in s['photos']) {
      photos.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14),
          child: pw.Image(pw.MemoryImage(await image(f['id'])), height: 170),
        ),
      );
    }
    final sig = pw.MemoryImage(await image(s['signature']['id']));
    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(38),
        footer: (c) => pw.Text(
          'DEMO CONTENT · ${c.pageNumber}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        build: (_) => [
          pw.Image(logo, width: 130, height: 56),
          pw.SizedBox(height: 18),
          pw.Text(
            s['brand']['reportTitle'],
            style: const pw.TextStyle(fontSize: 21),
          ),
          pw.Text(
            '${s['siteName']}\n${s['assetCode']} · ${s['assetName']}\n${s['technicianName']} · ${s['submittedAt']}\n${s['checklistName']} · Version ${s['checklistVersion']}',
          ),
          pw.SizedBox(height: 15),
          pw.Text('Result: ${s['result']}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: ['Checkpoint', 'Answer'],
            data: [
              for (final q in s['questions'])
                [q['label'], '${s['answers'][q['key']] ?? ''}'],
            ],
            headerStyle: const pw.TextStyle(fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 15),
          pw.Text(
            'Findings\n${s['notes']}\n\nService: ${s['serviceType']}\nWork performed\n${s['workPerformed']}\n\nParts / materials\n${s['partsUsed']}',
          ),
          ...photos,
          pw.SizedBox(height: 15),
          pw.Container(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Technician signature'),
            pw.SizedBox(height: 8),
            pw.Image(sig, width: 180, height: 65),
            pw.SizedBox(height: 6),
            pw.Text(s['technicianName']),
            pw.SizedBox(height: 15),
            pw.Text(s['brand']['footer'], style: const pw.TextStyle(fontSize: 8)),
          ])),
        ],
      ),
    );
    return doc.save();
  }

  Future<dynamic> demoCall(String path, String method, Json b) async {
    final uri = Uri.parse(path),
        parts = uri.path.split('/'),
        id = parts.length > 1 ? parts[1] : '',
        d = db!,
        assets = d['assets'] as List,
        records = d['inspections'] as List,
        templates = d['checklists'] as List,
        defects = d['defects'] as List;
    Json asset(String id) => obj(assets.firstWhere((a) => a['id'] == id));
    Json record(String id) {
      final r = obj(records.firstWhere((r) => r['id'] == id));
      return {...r, 'asset': asset(r['asset_id'])};
    }

    dynamic out;
    if (path == 'overview')
      return {
        'assets': assets.length,
        'inspections': records.where((r) => r['status'] == 'submitted').length,
        'drafts': records.where((r) => r['status'] == 'draft').length,
        'sites': (d['sites'] as List).length,
        'openDefects': defects.where((r) => r['status'] != 'closed').length,
      };
    if (path == 'sites') return clone(d['sites']);
    if (parts[0] == 'checklists')
      return clone(
        templates
            .where(
              (t) =>
                  uri.queryParameters['category'] == null ||
                  t['category'] == uri.queryParameters['category'],
            )
            .toList(),
      );
    if (path == 'settings') return clone(d['settings']);
    if (parts[0] == 'assets') {
      if (id == 'resolve') {
        final q = uri.queryParameters['q'] ?? '';
        return clone(
          assets.firstWhere(
            (a) =>
                a['qr_token'] == q ||
                a['code'].toString().toLowerCase() == q.toLowerCase(),
            orElse: () => throw Exception('No matching equipment found.'),
          ),
        );
      }
      if (id.isEmpty && method == 'GET') return clone(assets);
      if (id.isEmpty) {
        final site = (d['sites'] as List).firstWhere(
          (s) => s['id'] == b['siteId'],
        );
        out = {
          'id': newId(),
          'site_id': site['id'],
          'site_name': site['name'],
          'name': b['name'],
          'category': b['category'],
          'code': 'FYR-${(assets.length + 1).toString().padLeft(5, '0')}',
          'qr_token': newId() + newId(),
          'serial_number': b['serialNumber'] ?? '',
          'position': b['position'] ?? '',
        };
        assets.add(out);
      } else if (parts.length > 2 && parts[2] == 'history') {
        return clone(
          records
              .where((r) => r['asset_id'] == id && r['status'] == 'submitted')
              .toList(),
        );
      } else {
        return asset(id);
      }
    }
    if (parts[0] == 'inspections') {
      if (id.isEmpty && method == 'GET')
        return clone(
          records
              .where(
                (r) =>
                    uri.queryParameters['status'] == null ||
                    r['status'] == uri.queryParameters['status'],
              )
              .map(
                (r) => {
                  ...r,
                  'code': asset(r['asset_id'])['code'],
                  'asset_name': asset(r['asset_id'])['name'],
                  'site_name': asset(r['asset_id'])['site_name'],
                  'result': r['snapshot']?['result'],
                  'technician_name': user!['name'],
                },
              )
              .toList(),
        );
      if (id.isEmpty) {
        final t = templates.firstWhere((t) => t['id'] == b['templateId']);
        out = {
          'id': newId(),
          'asset_id': b['assetId'],
          'version_id': t['current_version_id'],
          'technician_id': user!['id'],
          'status': 'draft',
          'answers': <String, dynamic>{},
          'notes': '',
          'service_type': 'Inspection',
          'work_performed': '',
          'parts_used': '',
          'photo_ids': [],
          'signature_id': null,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'checklist': {...clone<Json>(obj(t)), 'template_name': t['name']},
        };
        records.add(out);
        out = record(out['id']);
      } else {
        final r = records.firstWhere((r) => r['id'] == id);
        if (method == 'PATCH') {
          if (r['status'] != 'draft')
            throw Exception('Submitted records cannot be changed.');
          for (final e in {
            'answers': 'answers',
            'notes': 'notes',
            'serviceType': 'service_type',
            'workPerformed': 'work_performed',
            'partsUsed': 'parts_used',
            'photoIds': 'photo_ids',
            'signatureId': 'signature_id',
          }.entries) {
            r[e.value] = b[e.key];
          }
          r['updated_at'] = DateTime.now().toIso8601String();
          out = record(id);
        } else if (method == 'DELETE') {
          if (r['status'] != 'draft')
            throw Exception('Submitted records cannot be deleted.');
          records.remove(r);
          out = {'deleted': true};
        } else if (method == 'POST' && parts.length > 2) {
          if (r['status'] == 'submitted')
            return {'id': id, 'status': 'submitted', 'replayed': true};
          final t = r['checklist'], answers = r['answers'], failed = [];
          for (final q in t['questions']) {
            final a = answers[q['key']];
            if (q['required'] == true && (a == null || a == ''))
              throw Exception('Answer every required checkpoint.');
            if (a == 'Fail' ||
                (q['failValue'] != null && '$a' == q['failValue']))
              failed.add(q);
          }
          if (failed.isNotEmpty && r['notes'].toString().trim().isEmpty)
            throw Exception('Describe failed checklist items.');
          if (t['require_photo'] == true && (r['photo_ids'] as List).isEmpty)
            throw Exception('Attach an equipment photo.');
          if (r['signature_id'] == null) throw Exception('Add your signature.');
          final a = asset(r['asset_id']),
              now = DateTime.now().toIso8601String();
          r['status'] = 'submitted';
          r['submitted_at'] = now;
          r['snapshot'] = {
            'id': id,
            'assetId': a['id'],
            'assetCode': a['code'],
            'assetName': a['name'],
            'siteId': a['site_id'],
            'siteName': a['site_name'],
            'category': a['category'],
            'position': a['position'],
            'serialNumber': a['serial_number'],
            'technicianName': user!['name'],
            'submittedAt': now,
            'checklistName': t['name'],
            'checklistVersion': t['version_number'],
            'questions': clone(t['questions']),
            'answers': clone(answers),
            'notes': r['notes'],
            'serviceType': r['service_type'],
            'workPerformed': r['work_performed'],
            'partsUsed': r['parts_used'],
            'brand': clone(d['settings']),
            'photos': (r['photo_ids'] as List).map((id) => {'id': id}).toList(),
            'signature': {'id': r['signature_id']},
            'result': failed.isNotEmpty ? 'Attention required' : 'Passed',
          };
          for (final q in failed) {
            if (!defects.any(
              (x) =>
                  x['asset_id'] == a['id'] &&
                  x['question_key'] == q['key'] &&
                  x['status'] != 'closed',
            ))
              defects.insert(0, {
                'id': newId(),
                'asset_id': a['id'],
                'site_id': a['site_id'],
                'asset_name': a['name'],
                'code': a['code'],
                'site_name': a['site_name'],
                'question_key': q['key'],
                'title': q['label'],
                'status': 'open',
                'priority': 'High',
                'assigned_to': user!['id'],
                'assigned_name': user!['name'],
                'events': [
                  {
                    'transition': 'created',
                    'notes': r['notes'],
                    'actor_name': user!['name'],
                    'photo_ids': [],
                    'created_at': now,
                  },
                ],
              });
          }
          out = {
            'id': id,
            'status': 'submitted',
            'result': r['snapshot']['result'],
          };
        } else {
          return record(id);
        }
      }
    }
    if (parts[0] == 'defects') {
      if (id.isEmpty) return clone(defects);
      final r = defects.firstWhere((r) => r['id'] == id);
      if (method == 'POST') {
        if ((b['notes'] ?? '').toString().trim().length < 3)
          throw Exception('Describe the corrective work.');
        if (!['start', 'resolve'].contains(b['transition']) ||
            r['status'] == 'resolved')
          throw Exception('Manager verification is required.');
        r['status'] = b['transition'] == 'start' ? 'in_progress' : 'resolved';
        r['events'].add({
          'transition': b['transition'],
          'notes': b['notes'],
          'actor_name': user!['name'],
          'photo_ids': b['photoIds'] ?? [],
          'created_at': DateTime.now().toIso8601String(),
        });
        out = r;
      } else {
        return clone(r);
      }
    }
    if (out == null)
      throw Exception('This action is unavailable in the demonstration.');
    await persist();
    return clone(out);
  }
}
