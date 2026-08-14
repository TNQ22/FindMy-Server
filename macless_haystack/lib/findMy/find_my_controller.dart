import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/findMy/models.dart';
import 'package:macless_haystack/findMy/reports_fetcher.dart';
import 'package:logger/logger.dart';
import 'package:pointycastle/export.dart';
import 'package:universal_html/html.dart' as html;

// ignore: implementation_imports
import 'package:pointycastle/src/platform_check/platform_check.dart';

// ignore: implementation_imports
import 'package:pointycastle/src/utils.dart' as pc_utils;

import '../preferences/user_preferences_model.dart';

class FindMyController {
  static const _storage = FlutterSecureStorage();
  static final ECCurve_secp224r1 _curveParams = ECCurve_secp224r1();
  static final HashMap _keyCache = HashMap();

  static final logger = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

  /// Starts a new, fetches and decrypts all location reports
  /// for the given [FindMyKeyPair].
  /// Returns a list of [FindMyLocationReport]'s.
  static Future<List<FindMyLocationReport>> computeResults(
      List<FindMyKeyPair> keyPairs, String? url) async {
    for (var kp in keyPairs) {
      await _loadPrivateKey(kp);
    }

    String resolvedUrl = url ?? '';
    try {
      if (kIsWeb) {
        String origin = html.window.location.origin;
        if (origin.startsWith('http')) {
          resolvedUrl = '$origin/api/reports/fetch';
        }
      }
    } catch (_) {}

    if (resolvedUrl.isEmpty) {
      resolvedUrl = 'http://localhost:6176/api/reports/fetch';
    } else if (!resolvedUrl.contains('/api/reports/fetch') && !resolvedUrl.endsWith('/fetch')) {
      if (resolvedUrl.endsWith('/')) {
        resolvedUrl = '${resolvedUrl}api/reports/fetch';
      } else {
        resolvedUrl = '$resolvedUrl/api/reports/fetch';
      }
    }

    Map map = <String, Object>{};
    map['keyPair'] = keyPairs;
    map['url'] = resolvedUrl;
    map['daysToFetch'] =
        Settings.getValue<int>(numberOfDaysToFetch, defaultValue: 30)!;
    map['user'] = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    map['pass'] = Settings.getValue<String>(endpointPass, defaultValue: '')!;
    return compute(_getListedReportResults, map);
  }

  /// Fetches and decrypts the location reports for the given
  /// [FindMyKeyPair] from apples FindMy Network.
  /// Returns a list of [FindMyLocationReport].
  static Future<List<FindMyLocationReport>> _getListedReportResults(
      Map map) async {
    List<FindMyLocationReport> results = <FindMyLocationReport>[];
    List<FindMyKeyPair> keyPairs = map['keyPair'];
    var url = map['url'];
    int daysToFetch = map['daysToFetch'];
    Map<String, FindMyKeyPair> hashedKeyKeyPairsMap = {
      for (var e in keyPairs) e.getHashedAdvertisementKey(): e
    };

    List jsonResults = await ReportsFetcher.fetchLocationReports(
        hashedKeyKeyPairsMap.keys, daysToFetch, url, map['user'], map['pass']);
    for (var result in jsonResults) {
      String repId = result['id']?.toString() ?? '';
      FindMyKeyPair? keyPair = hashedKeyKeyPairsMap[repId];
      if (keyPair == null && keyPairs.isNotEmpty) {
        keyPair = keyPairs.first;
      }
      if (keyPair == null) continue;

      var currentReport = FindMyLocationReport.decrypted(
        result,
        keyPair.getBase64PrivateKey(),
        keyPair.getHashedAdvertisementKey(),
      );
      try {
        await currentReport.decrypt();
      } catch (e) {
        logger.e('Decrypting report failed (Key pair: ${keyPair.hashedPublicKey}): $e');
      }
      results.add(currentReport);
    }
    return results;
  }

  /// Loads the private key from the local cache or secure storage and adds it
  /// to the given [FindMyKeyPair].
  static Future<void> _loadPrivateKey(FindMyKeyPair keyPair) async {
    String? privateKey;
    if (!_keyCache.containsKey(keyPair.hashedPublicKey)) {
      privateKey = await _storage.read(key: keyPair.hashedPublicKey);
      final newKey =
          _keyCache.putIfAbsent(keyPair.hashedPublicKey, () => privateKey);
      assert(newKey == privateKey);
    } else {
      privateKey = _keyCache[keyPair.hashedPublicKey];
    }
    keyPair.privateKeyBase64 = privateKey!;
  }

  /// Derives an [ECPublicKey] from a given [ECPrivateKey] on the given curve.
  static ECPublicKey _derivePublicKey(ECPrivateKey privateKey) {
    final pk = _curveParams.G * privateKey.d;
    final publicKey = ECPublicKey(pk, _curveParams);
    return publicKey;
  }

  /// Returns the to the base64 encoded given hashed public key
  /// corresponding [FindMyKeyPair] from the local [FlutterSecureStorage].
  static Future<FindMyKeyPair> getKeyPair(String base64HashedPublicKey) async {
    final privateKeyBase64 = await _storage.read(key: base64HashedPublicKey);

    ECPrivateKey privateKey = ECPrivateKey(
        pc_utils.decodeBigIntWithSign(1, base64Decode(privateKeyBase64!)),
        _curveParams);
    ECPublicKey publicKey = _derivePublicKey(privateKey);

    return FindMyKeyPair(
        publicKey, base64HashedPublicKey, privateKey, DateTime.now(), -1);
  }

  /// Imports a base64 encoded private key to the local [FlutterSecureStorage].
  /// Returns a [FindMyKeyPair] containing the corresponding [ECPublicKey].
  static Future<FindMyKeyPair> importKeyPair(String privateKeyBase64) async {
    final privateKeyBytes = base64Decode(privateKeyBase64);
    final ECPrivateKey privateKey = ECPrivateKey(
        pc_utils.decodeBigIntWithSign(1, privateKeyBytes), _curveParams);
    final ECPublicKey publicKey = _derivePublicKey(privateKey);
    final hashedPublicKey = getHashedPublicKey(publicKey: publicKey);
    final keyPair = FindMyKeyPair(
        publicKey, hashedPublicKey, privateKey, DateTime.now(), -1);

    await _storage.write(
        key: hashedPublicKey, value: keyPair.getBase64PrivateKey());

    return keyPair;
  }

  /// Generates a [ECCurve_secp224r1] keypair.
  /// Returns the newly generated keypair as a [FindMyKeyPair] object.
  static Future<FindMyKeyPair> generateKeyPair() async {
    final ecCurve = ECCurve_secp224r1();
    final secureRandom = SecureRandom('Fortuna')
      ..seed(
          KeyParameter(Platform.instance.platformEntropySource().getBytes(32)));
    ECKeyGenerator keyGen = ECKeyGenerator()
      ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(ecCurve), secureRandom));

    final newKeyPair = keyGen.generateKeyPair();
    final ECPublicKey publicKey = newKeyPair.publicKey;
    final ECPrivateKey privateKey = newKeyPair.privateKey;
    final hashedKey = getHashedPublicKey(publicKey: publicKey);
    final keyPair =
        FindMyKeyPair(publicKey, hashedKey, privateKey, DateTime.now(), -1);
    await _storage.write(key: hashedKey, value: keyPair.getBase64PrivateKey());

    return keyPair;
  }

  static Future<void> savePrivateKeyToStorage(String hashedPublicKey, String privateKeyBase64) async {
    _keyCache[hashedPublicKey] = privateKeyBase64;
    await _storage.write(key: hashedPublicKey, value: privateKeyBase64);
  }

  /// Returns hashed, base64 encoded public key for given [publicKeyBytes]
  /// or for an [ECPublicKey] object [publicKey], if [publicKeyBytes] equals null.
  /// Returns the base64 encoded hashed public key as a [String].
  static String getHashedPublicKey(
      {Uint8List? publicKeyBytes, ECPublicKey? publicKey}) {
    var pkBytes = publicKeyBytes ?? publicKey!.Q!.getEncoded(false);
    final shaDigest = SHA256Digest();
    shaDigest.update(pkBytes, 0, pkBytes.lengthInBytes);
    Uint8List out = Uint8List(shaDigest.digestSize);
    shaDigest.doFinal(out, 0);
    return base64Encode(out);
  }

  /// Calculates the static random MAC address for a given base64 private key.
  static String calculateMacAddress(String privateKeyBase64) {
    try {
      final privateKeyBytes = base64Decode(privateKeyBase64);
      final ECPrivateKey privateKey = ECPrivateKey(
          pc_utils.decodeBigIntWithSign(1, privateKeyBytes), _curveParams);
      final ECPublicKey publicKey = _derivePublicKey(privateKey);
      var pkBytes = publicKey.Q!.getEncoded(false); 
      // pkBytes[0] is 0x04. The X coordinate is pkBytes[1] to pkBytes[28].
      final macBytes = pkBytes.sublist(1, 7);
      macBytes[0] |= 0xC0; // Set two most significant bits to 1 (Static Random Address)
      return macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (e) {
      return "Unknown";
    }
  }
}
