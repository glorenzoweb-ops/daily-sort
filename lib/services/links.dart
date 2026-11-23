import 'package:url_launcher/url_launcher.dart';

import 'share.dart';

/// Apple's standard terms for apps that don't write their own.
const termsUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// Served with the web build (`web/privacy.html`, `web/support.html`).
const privacyUrl = '${shareUrl}privacy.html';
const supportUrl = '${shareUrl}support.html';

Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
