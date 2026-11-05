import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:webcrypto/webcrypto.dart';

class FormLogicAssetsException implements Exception {
  const FormLogicAssetsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FormLogicAssets {
  const FormLogicAssets({
    required this.version,
    required this.shim,
    required this.bundle,
    required this.conformance,
    required this.parity,
    required this.checks,
  });

  static const expectedVersion = '1.3.0';
  static const _dir = 'assets/form_logic/';
  static const _loaded = [
    'form-logic-host-shim.js',
    'form-logic.bundle.js',
    'form-logic-conformance.json',
  ];

  final String version;
  final String shim;
  final String bundle;
  final String conformance;
  final String parity;
  final List<String> checks;

  static Future<FormLogicAssets> loadVerified() async {
    final manifestBytes = await _bytes('manifest.json');
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    if (manifest['version'] != expectedVersion) {
      throw FormLogicAssetsException(
        'form logic ${manifest['version']} is bundled, '
        'this app expects $expectedVersion',
      );
    }
    final files = (manifest['files'] as List).cast<Map<String, dynamic>>();
    final checks = <String>[];

    final lines = StringBuffer();
    for (final f in files) {
      lines.write('${f['path']}:${f['sha256']}\n');
    }
    final overall = await _sha256(utf8.encode(lines.toString()));
    if (overall != manifest['sha256']) {
      throw FormLogicAssetsException(
        'manifest overall hash mismatch: $overall != ${manifest['sha256']}',
      );
    }
    checks.add('overall ${overall.substring(0, 12)}… ok');

    final texts = <String, String>{};
    for (final name in _loaded) {
      final entry = files.firstWhere(
        (f) => f['path'] == name,
        orElse: () =>
            throw FormLogicAssetsException('$name is not in the manifest'),
      );
      final bytes = await _bytes(name);
      final hash = await _sha256(bytes);
      if (hash != entry['sha256'] || bytes.length != entry['size']) {
        throw FormLogicAssetsException(
          '$name refused: ${bytes.length} bytes, sha256 $hash, '
          'manifest says ${entry['size']} bytes, ${entry['sha256']}',
        );
      }
      texts[name] = utf8.decode(bytes);
      checks.add('$name ${hash.substring(0, 12)}… ok');
    }

    return FormLogicAssets(
      version: manifest['version'] as String,
      shim: texts[_loaded[0]]!,
      bundle: texts[_loaded[1]]!,
      conformance: texts[_loaded[2]]!,
      parity: await rootBundle.loadString('${_dir}parity_vectors.json'),
      checks: checks,
    );
  }

  static Future<Uint8List> _bytes(String name) async {
    final data = await rootBundle.load('$_dir$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<String> _sha256(List<int> bytes) async {
    final digest = await Hash.sha256.digestBytes(bytes);
    final sb = StringBuffer();
    for (final b in digest) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
