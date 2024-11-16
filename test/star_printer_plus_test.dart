import 'package:flutter_test/flutter_test.dart';
import 'package:star_printer_plus/star_printer_plus.dart';
import 'package:star_printer_plus/star_printer_plus_platform_interface.dart';
import 'package:star_printer_plus/star_printer_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockStarPrinterPlusPlatform
    with MockPlatformInterfaceMixin
    implements StarPrinterPlusPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final StarPrinterPlusPlatform initialPlatform = StarPrinterPlusPlatform.instance;

  test('$MethodChannelStarPrinterPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelStarPrinterPlus>());
  });

  test('getPlatformVersion', () async {
    StarPrinterPlus starPrinterPlusPlugin = StarPrinterPlus();
    MockStarPrinterPlusPlatform fakePlatform = MockStarPrinterPlusPlatform();
    StarPrinterPlusPlatform.instance = fakePlatform;

    expect(await starPrinterPlusPlugin.getPlatformVersion(), '42');
  });
}
