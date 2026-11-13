import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

/// Version sent to Odoo and shown in About.
const String kAloVersion = '1.5.1-alo.2';

/// Odoo base used by the support-code fallback. Change it here only.
/// Staging value: replace with the production domain when going live.
const String kAloDefaultOdooBase = 'https://staging.alo.zone';

const String _kOptOdooUrl = 'alo-odoo-url';
const String _kOptDeviceToken = 'alo-device-token';
const String _kOptLastHello = 'alo-last-hello';
const String _kApiPrefix = '/alo_support/api/v1';

final RxBoolLike aloLinked = RxBoolLike();

/// Minimal notifier so the home page can rebuild when link state changes.
class RxBoolLike extends ChangeNotifier {
  bool _v = false;
  bool get value => _v;
  set value(bool v) {
    if (v != _v) {
      _v = v;
      notifyListeners();
    }
  }
}

String _getOpt(String key) => bind.mainGetLocalOption(key: key);
void _setOpt(String key, String value) =>
    bind.mainSetLocalOption(key: key, value: value);

/// True only for https URLs whose host is under alo.zone.
bool isAllowedOdooBase(String? base) {
  if (base == null) return false;
  final uri = Uri.tryParse(base);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  return uri.host == 'alo.zone' || uri.host.endsWith('.alo.zone');
}

bool _isToken(String s) => RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(s);

const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Returns the 8 characters of a support code, or null if it is not valid.
String? normalizeSupportCode(String input) {
  final s = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (s.length != 8) return null;
  for (final c in s.split('')) {
    if (!_codeAlphabet.contains(c)) return null;
  }
  return s;
}

bool aloIsLinked() => _getOpt(_kOptDeviceToken).isNotEmpty;

void aloRefreshLinkState() {
  aloLinked.value = aloIsLinked();
}

Uri? _parse(List<String>? cmdArgs, Uri? uri, String? uriString) {
  if (uri != null) return uri;
  if (uriString != null) return Uri.tryParse(uriString);
  if (cmdArgs != null && cmdArgs.isNotEmpty) return Uri.tryParse(cmdArgs[0]);
  return null;
}

/// Handles `alosupport://enroll?...`. Other links are left to the normal handler.
bool aloHandleUriLink(List<String>? cmdArgs, Uri? uri, String? uriString) {
  final u = _parse(cmdArgs, uri, uriString);
  if (u == null || u.scheme != 'alosupport' || u.authority != 'enroll') {
    return false;
  }
  final base = u.queryParameters['u'];
  final token = u.queryParameters['t'];
  if (!isAllowedOdooBase(base) || token == null || !_isToken(token)) {
    Timer(const Duration(seconds: 1), () {
      _showMessage(translate('Invalid assistance link'));
    });
    return true;
  }
  Timer(const Duration(milliseconds: 500), () {
    _confirmEnroll(Uri.parse(base!).origin, token);
  });
  return true;
}

/// Support-code fallback (button on the home page).
Future<void> aloEnrollWithCode(String input) async {
  final code = normalizeSupportCode(input);
  if (code == null) {
    _showMessage(translate('Invalid assistance code'));
    return;
  }
  _confirmEnroll(kAloDefaultOdooBase, code);
}

void _showMessage(String text) {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        content: Text(text),
        actions: [dialogButton('OK', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      ));
}

void _confirmEnroll(String base, String secret) {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      _doEnroll(base, secret);
    }

    return CustomAlertDialog(
      title: Text(translate('Link this PC to the support ticket')),
      content: Text(translate("Link this PC to the support ticket? ALO will receive: this program's ID, the PC name and the times of support connections.")),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Link', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

String _deviceName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return '';
  }
}

String _platformName() => Platform.isMacOS ? 'macos' : 'windows';

String _errorText(String code) {
  switch (code) {
    case 'expired':
      return translate('This link or code has expired');
    case 'already_used':
      return translate('This link or code was already used');
    case 'id_conflict':
      return translate('This program is linked to another customer');
    case 'rate_limited':
      return translate('Too many attempts, try again later');
    case 'invalid':
      return translate('Invalid assistance link');
    default:
      return translate('Could not link, try again');
  }
}

Future<void> _doEnroll(String base, String secret) async {
  String? error;
  Map<String, dynamic>? data;
  try {
    final myId = await bind.mainGetMyId();
    final res = await http
        .post(Uri.parse('$base$_kApiPrefix/enroll'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'secret': secret,
              'rustdesk_id': myId,
              'device_name': _deviceName(),
              'platform': _platformName(),
              'app_version': kAloVersion,
            }))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 429) {
      error = 'rate_limited';
    } else if (res.statusCode == 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map<String, dynamic> && j['ok'] == true) {
        data = j;
      } else if (j is Map && j['error'] is String) {
        error = j['error'] as String;
      } else {
        error = 'network';
      }
    } else {
      error = 'network';
    }
  } catch (_) {
    error = 'network';
  }
  if (data == null) {
    _showMessage(_errorText(error ?? 'network'));
    return;
  }
  final token = data['device_token'];
  if (token is! String || token.length < 20) {
    _showMessage(_errorText('network'));
    return;
  }
  _setOpt(_kOptOdooUrl, base);
  _setOpt(_kOptDeviceToken, token);
  _setOpt(_kOptLastHello, DateTime.now().millisecondsSinceEpoch.toString());
  aloRefreshLinkState();
  final number = data['ticket_number']?.toString() ?? '';
  final title = data['ticket_title']?.toString() ?? '';
  _showMessage(
      '${translate('Linked to ticket')} $number: $title'.replaceAll(' : ', ': '));
}

/// Sent at every start, at most once an hour. Silent on network errors.
Future<void> aloHello() async {
  aloRefreshLinkState();
  final base = _getOpt(_kOptOdooUrl);
  final token = _getOpt(_kOptDeviceToken);
  if (token.isEmpty || !isAllowedOdooBase(base)) return;
  final last = int.tryParse(_getOpt(_kOptLastHello)) ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - last >= 0 && now - last < const Duration(hours: 1).inMilliseconds) {
    return;
  }
  try {
    final myId = await bind.mainGetMyId();
    final res = await http
        .post(Uri.parse('$base$_kApiPrefix/hello'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_token': token,
              'rustdesk_id': myId,
              'device_name': _deviceName(),
              'app_version': kAloVersion,
            }))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is Map && j['ok'] == true) {
      _setOpt(_kOptLastHello, now.toString());
    } else if (j is Map && j['error'] == 'unknown_token') {
      _setOpt(_kOptDeviceToken, '');
      _setOpt(_kOptOdooUrl, '');
      aloRefreshLinkState();
    }
  } catch (_) {}
}

/// Home page block: shown only while the program is not linked.
class AloLinkCard extends StatefulWidget {
  const AloLinkCard({Key? key}) : super(key: key);
  @override
  State<AloLinkCard> createState() => _AloLinkCardState();
}

class _AloLinkCardState extends State<AloLinkCard> {
  final _ctl = TextEditingController();

  void _onChange() => setState(() {});

  @override
  void initState() {
    super.initState();
    aloLinked.addListener(_onChange);
    aloRefreshLinkState();
  }

  @override
  void dispose() {
    aloLinked.removeListener(_onChange);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (aloLinked.value) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('Assistance code'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(translate('Enter the code received from ALO to link this PC'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(
            controller: _ctl,
            autofocus: true,
            style: const TextStyle(fontSize: 26, letterSpacing: 2),
            decoration: const InputDecoration(
              hintText: 'XXXX-XXXX',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onSubmitted: (v) => aloEnrollWithCode(v),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => aloEnrollWithCode(_ctl.text),
              child: Text(translate('Link')),
            ),
          ),
        ],
      ),
    );
  }
}
