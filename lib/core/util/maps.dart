import 'package:url_launcher/url_launcher.dart';

/// Google Maps 導航 deep link（地址搜尋版，免 pickup 座標）
Future<bool> openMapsNavigation(String address) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
