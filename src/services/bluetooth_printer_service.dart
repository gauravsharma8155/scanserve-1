import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefBtMac = 'bt_printer_mac';
const String _prefBtName = 'bt_printer_name';
const String _prefBtPaperSize = 'bt_printer_paper_size'; // '58' or '80'

class BluetoothPrinterService {
  /// Request necessary Bluetooth runtime permissions on Android and iOS
  Future<bool> requestBluetoothPermissions() async {
    if (kIsWeb) return true;

    try {
      if (Platform.isAndroid) {
        // Request Bluetooth permissions for Android 12+ (API 31+)
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();

        final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
        final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;

        if (connectGranted || scanGranted) {
          return true;
        }

        // Check if plugin native status is granted
        final pluginGranted = await PrintBluetoothThermal.isPermissionBluetoothGranted
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (pluginGranted) return true;

        // Fallback for Android <= 11 (requires location permission for Bluetooth)
        final locStatus = await Permission.location.request();
        return locStatus.isGranted;
      } else if (Platform.isIOS) {
        final status = await Permission.bluetooth.request();
        return status.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Error requesting Bluetooth permissions: $e');
      return false;
    }
  }

  /// Check whether Bluetooth permissions have been granted
  Future<bool> checkPermissionsGranted() async {
    if (kIsWeb) return true;

    try {
      if (Platform.isAndroid) {
        final connectGranted = await Permission.bluetoothConnect.isGranted;
        if (connectGranted) return true;

        final pluginGranted = await PrintBluetoothThermal.isPermissionBluetoothGranted
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (pluginGranted) return true;

        return await Permission.location.isGranted;
      } else if (Platform.isIOS) {
        return await Permission.bluetooth.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Error checking Bluetooth permissions: $e');
      return false;
    }
  }

  /// Open device app settings if permissions were permanently denied
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Check if Bluetooth is turned ON on the device
  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (e) {
      debugPrint('⚠️ Error checking bluetoothEnabled: $e');
      return false;
    }
  }

  /// Check if a printer is actively connected
  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (e) {
      debugPrint('⚠️ Error checking connectionStatus: $e');
      return false;
    }
  }

  /// Get list of paired Bluetooth devices
  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
    } catch (e) {
      debugPrint('⚠️ Error getting pairedBluetooths: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth printer and save it as default
  Future<bool> connect(String macAddress, {String? printerName}) async {
    try {
      final isConnectedAlready = await isConnected();
      if (isConnectedAlready) {
        await PrintBluetoothThermal.disconnect
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
      }

      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      ).timeout(const Duration(seconds: 7), onTimeout: () => false);

      if (result) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefBtMac, macAddress);
        if (printerName != null) {
          await prefs.setString(_prefBtName, printerName);
        }
        debugPrint('✅ Connected to Bluetooth printer: $macAddress ($printerName)');
      } else {
        debugPrint('❌ Failed to connect to Bluetooth printer: $macAddress');
      }

      return result;
    } catch (e) {
      debugPrint('⚠️ Error connecting to Bluetooth printer: $e');
      return false;
    }
  }

  /// Disconnect from current printer
  Future<bool> disconnect() async {
    try {
      return await PrintBluetoothThermal.disconnect
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (e) {
      debugPrint('⚠️ Error disconnecting printer: $e');
      return false;
    }
  }

  /// Check if the user has a saved printer in settings
  Future<bool> hasConfiguredPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_prefBtMac);
    return mac != null && mac.trim().isNotEmpty;
  }

  /// Retrieve saved printer details
  Future<Map<String, String>> getSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'mac': prefs.getString(_prefBtMac) ?? '',
      'name': prefs.getString(_prefBtName) ?? 'Thermal Printer',
      'paperSize': prefs.getString(_prefBtPaperSize) ?? '58',
    };
  }

  /// Set preferred paper size ('58' or '80')
  Future<void> setPaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBtPaperSize, size == '80' ? '80' : '58');
  }

  /// Clear saved printer
  Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefBtMac);
    await prefs.remove(_prefBtName);
    await disconnect();
  }

  /// Ensure connection is active before printing; auto-reconnect if needed
  Future<bool> ensureConnected() async {
    final connected = await isConnected();
    if (connected) return true;

    final saved = await getSavedPrinter();
    final mac = saved['mac'];
    if (mac == null || mac.isEmpty) return false;

    debugPrint('🔄 Reconnecting to saved Bluetooth printer: $mac...');
    return await connect(mac, printerName: saved['name']);
  }

  /// Format Kitchen Order Ticket into ESC/POS binary commands
  Future<List<int>> buildKOTBytes({
    required String orderId,
    required List<dynamic> items,
    bool isAddOn = false,
    String? tableNumber,
    String? customerName,
    String? restaurantName,
    String paperSize = '58',
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );
    final List<int> bytes = [];

    // Header: Restaurant Name
    bytes.addAll(
      generator.text(
        restaurantName ?? 'ScanServe',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      ),
    );

    // KOT Type Badge
    if (isAddOn) {
      bytes.addAll(
        generator.text(
          '*** ADD-ON KOT ***',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
      );
    } else {
      bytes.addAll(
        generator.text(
          '*** KITCHEN ORDER TICKET ***',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
      );
    }

    bytes.addAll(generator.hr(ch: '='));

    // Table & Order Information
    if (tableNumber != null && tableNumber.trim().isNotEmpty) {
      bytes.addAll(
        generator.text(
          'TABLE: $tableNumber',
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size1,
          ),
        ),
      );
    }

    final shortId = orderId.length > 6
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : orderId;
    bytes.addAll(
      generator.text('Order ID: #$shortId', styles: const PosStyles(bold: true)),
    );

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    bytes.addAll(generator.text('Date: $dateStr'));

    if (customerName != null && customerName.trim().isNotEmpty) {
      bytes.addAll(generator.text('Customer: $customerName'));
    }

    bytes.addAll(generator.hr(ch: '-'));

    // Items Header (9 cols for item, 3 cols for qty = 12 total cols)
    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'ITEM',
          width: 9,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'QTY',
          width: 3,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
    );

    bytes.addAll(generator.hr(ch: '-'));

    // Items List
    int totalQuantity = 0;
    for (final raw in items) {
      String itemName = 'Item';
      int qty = 1;
      String? note;

      if (raw is Map) {
        final itemObj = raw['item'];
        if (itemObj is Map) {
          itemName = itemObj['branchName']?.toString() ??
              itemObj['name']?.toString() ??
              raw['name']?.toString() ??
              'Item';
        } else {
          itemName = raw['name']?.toString() ?? 'Item';
        }
        qty = (raw['quantity'] is num) ? (raw['quantity'] as num).toInt() : 1;
        note = raw['instruction']?.toString() ?? raw['note']?.toString();
      } else {
        try {
          itemName = (raw as dynamic).name ?? 'Item';
          qty = (raw as dynamic).quantity ?? 1;
        } catch (_) {}
      }

      totalQuantity += qty;

      bytes.addAll(
        generator.row([
          PosColumn(
            text: itemName,
            width: 9,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: 'x$qty',
            width: 3,
            styles: const PosStyles(
              align: PosAlign.right,
              bold: true,
              height: PosTextSize.size2,
            ),
          ),
        ]),
      );

      if (note != null && note.trim().isNotEmpty) {
        bytes.addAll(
          generator.text(
            '  * Note: $note',
            styles: const PosStyles(fontType: PosFontType.fontB),
          ),
        );
      }
    }

    bytes.addAll(generator.hr(ch: '-'));

    // Summary
    bytes.addAll(
      generator.text(
        'Total Items: ${items.length}  (Total Qty: $totalQuantity)',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );

    // Feed and Cut
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return bytes;
  }

  /// Format Customer Bill Receipt into ESC/POS binary commands
  Future<List<int>> buildBillBytes({
    required Map<String, dynamic> bill,
    String paperSize = '58',
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );
    final List<int> bytes = [];

    final restName = bill['restaurantName']?.toString() ?? 'RESTAURANT';
    final tableNum = bill['tableNumber']?.toString() ?? '-';

    bytes.addAll(
      generator.text(
        restName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        'Table: $tableNum',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );

    final now = DateTime.now();
    bytes.addAll(
      generator.text(
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );

    bytes.addAll(generator.hr(ch: '-'));

    // Items table (6 col Item, 2 col Qty, 4 col Price)
    bytes.addAll(
      generator.row([
        PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(
          text: 'Qty',
          width: 2,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Price',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
    );

    bytes.addAll(generator.hr(ch: '-'));

    final items = bill['items'] as List? ?? [];
    for (final i in items) {
      if (i is! Map) continue;
      final name = i['name']?.toString() ?? 'Item';
      final qty = i['quantity'] ?? 1;
      final price = num.tryParse((i['basePrice'] ?? 0).toString()) ?? 0;
      final total = price * (qty is num ? qty : 1);

      bytes.addAll(
        generator.row([
          PosColumn(text: name, width: 6),
          PosColumn(
            text: '$qty',
            width: 2,
            styles: const PosStyles(align: PosAlign.center),
          ),
          PosColumn(
            text: '₹${total.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    bytes.addAll(generator.hr(ch: '-'));

    final subTotal = num.tryParse((bill['subTotal'] ?? 0).toString()) ?? 0;
    final gstRate = bill['gstRate'] ?? 0;
    final gstAmount = num.tryParse((bill['gstAmount'] ?? 0).toString()) ?? 0;
    final total = num.tryParse((bill['total'] ?? 0).toString()) ?? 0;

    bytes.addAll(
      generator.row([
        PosColumn(text: 'Subtotal:', width: 6),
        PosColumn(
          text: '₹${subTotal.toStringAsFixed(2)}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );

    if (gstAmount > 0) {
      bytes.addAll(
        generator.row([
          PosColumn(text: 'GST ($gstRate%):', width: 6),
          PosColumn(
            text: '₹${gstAmount.toStringAsFixed(2)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'TOTAL:',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: '₹${total.toStringAsFixed(2)}',
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      ]),
    );

    bytes.addAll(generator.hr(ch: '='));
    bytes.addAll(
      generator.text(
        'Thank You! Visit Again',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return bytes;
  }

  /// Direct KOT Print: Connects (if needed), generates bytes, and writes to printer
  Future<bool> printKOTDirect({
    required String orderId,
    required List<dynamic> items,
    bool isAddOn = false,
    String? tableNumber,
    String? customerName,
    String? restaurantName,
  }) async {
    final connected = await ensureConnected();
    if (!connected) {
      debugPrint('❌ Cannot print KOT: Bluetooth printer not connected.');
      return false;
    }

    final saved = await getSavedPrinter();
    final paperSize = saved['paperSize'] ?? '58';

    final bytes = await buildKOTBytes(
      orderId: orderId,
      items: items,
      isAddOn: isAddOn,
      tableNumber: tableNumber,
      customerName: customerName,
      restaurantName: restaurantName,
      paperSize: paperSize,
    );

    final success = await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    if (success) {
      debugPrint('🖨️ Direct Bluetooth KOT printed successfully for order $orderId!');
    } else {
      debugPrint('❌ Failed writing KOT bytes to Bluetooth printer.');
    }
    return success;
  }

  /// Direct Bill Print
  Future<bool> printBillDirect(Map<String, dynamic> bill) async {
    final connected = await ensureConnected();
    if (!connected) {
      debugPrint('❌ Cannot print Bill: Bluetooth printer not connected.');
      return false;
    }

    final saved = await getSavedPrinter();
    final paperSize = saved['paperSize'] ?? '58';

    final bytes = await buildBillBytes(
      bill: bill,
      paperSize: paperSize,
    );

    return await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  /// Print a test receipt to verify connection and paper alignment
  Future<bool> printTestTicket() async {
    final connected = await ensureConnected();
    if (!connected) return false;

    final saved = await getSavedPrinter();
    final paperSize = saved['paperSize'] ?? '58';

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    final List<int> bytes = [];
    bytes.addAll(
      generator.text(
        'ScanServe POS',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        '*** TEST RECEIPT ***',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Printer: ${saved['name']}'));
    bytes.addAll(generator.text('MAC: ${saved['mac']}'));
    bytes.addAll(generator.text('Paper Size: ${paperSize}mm'));
    bytes.addAll(generator.text('Status: Connected & Ready'));
    bytes.addAll(generator.text('Date: ${DateTime.now().toString().substring(0, 19)}'));
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.text(
        'Direct Bluetooth Printing OK!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
  }
}

/// Provider for BluetoothPrinterService
final bluetoothPrinterServiceProvider = Provider<BluetoothPrinterService>((ref) {
  return BluetoothPrinterService();
});
