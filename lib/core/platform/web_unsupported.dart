import 'package:flutter/material.dart';

/// 司機端不支援 web，這裡負責「講清楚」而不是讓它在半路炸掉。
///
/// 司機端依賴背景定位、系統定位權限對話框與 `dart:io` 的 `Platform`，
/// 這些在瀏覽器都沒有對應實作。沒有這道攔截的話，`flutter run -d chrome`
/// （預設進入點就是司機端）會噴
/// 「Unsupported operation: Platform._operatingSystem」——訊息完全看不出
/// 是「平台選錯了」，排查成本很高。
void runDriverWebUnsupportedApp() {
  runApp(const _WebUnsupportedApp());
}

class _WebUnsupportedApp extends StatelessWidget {
  const _WebUnsupportedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fleet 司機',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '司機端不支援瀏覽器',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '司機端需要背景定位與系統定位權限，瀏覽器沒有對應能力。'
                    '請改跑 Android 或 iOS。',
                  ),
                  const SizedBox(height: 20),
                  const Text('瀏覽器只支援乘客端：'),
                  const SizedBox(height: 6),
                  SelectableText(
                    'flutter run -d chrome -t lib/main_customer.dart',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      backgroundColor: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
