import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../services/bluetooth_printer_service.dart';
import '../../../services/kot_print_service.dart';
import '../../context/AuthContext.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _liveOrderKOT = false;
  bool _autoPrintKOT = false;
  bool _autoPrintBill = false;
  int? _selectedPrinterId;

  bool _isSavingLiveOrder = false;
  bool _isSavingAutoKOT = false;
  bool _isSavingAutoBill = false;
  bool _isSavingPrinterId = false;

  bool _isDetectingPrinters = false;
  List<Map<String, dynamic>> _availablePrinters = [];
  String? _printerError;

  // Direct Bluetooth Thermal Printer state
  bool _isBtConnected = false;
  String _savedBtName = '';
  String _savedBtMac = '';
  String _savedPaperSize = '58';
  bool _isBtScanning = false;
  bool _isBtConnecting = false;
  bool _isPrintingTest = false;
  List<BluetoothInfo> _pairedBtDevices = [];

  @override
  void initState() {
    super.initState();
    _initSettingsFromUser();
    _initBluetoothSettings();
  }

  Future<void> _initBluetoothSettings() async {
    final btService = ref.read(bluetoothPrinterServiceProvider);
    final connected = await btService.isConnected();
    final saved = await btService.getSavedPrinter();
    if (mounted) {
      setState(() {
        _isBtConnected = connected;
        _savedBtMac = saved['mac'] ?? '';
        _savedBtName = saved['name'] ?? '';
        _savedPaperSize = saved['paperSize'] ?? '58';
      });
    }
  }

  void _initSettingsFromUser() {
    final user = ref.read(authProvider).user;
    if (user != null) {
      final data = (user['data'] is Map) ? user['data'] : user;
      setState(() {
        _liveOrderKOT = data['liveOrderKOT'] == true;
        _autoPrintKOT = data['autoPrintKOT'] == true;
        _autoPrintBill = data['autoPrintBill'] == true;
        if (data['printNodePrinterId'] != null) {
          _selectedPrinterId = int.tryParse(data['printNodePrinterId'].toString());
        }
      });
    }
  }

  Future<void> _toggleLiveOrderKOT(bool val) async {
    final previous = _liveOrderKOT;
    setState(() {
      _liveOrderKOT = val;
      _isSavingLiveOrder = true;
    });

    try {
      final kotService = ref.read(kotPrintServiceProvider);
      await kotService.updatePrinterSettings(liveOrderKOT: val);
      await ref.read(authProvider.notifier).loadSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(val ? 'Live Order KOT enabled' : 'Live Order KOT disabled'),
            backgroundColor: const Color(0xFF8B5CF6),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Rollback on failure
      if (mounted) {
        setState(() => _liveOrderKOT = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingLiveOrder = false);
    }
  }

  Future<void> _toggleAutoPrintKOT(bool val) async {
    // Cannot toggle if liveOrderKOT is on
    if (_liveOrderKOT) return;

    final previous = _autoPrintKOT;
    setState(() {
      _autoPrintKOT = val;
      _isSavingAutoKOT = true;
    });

    try {
      final kotService = ref.read(kotPrintServiceProvider);
      await kotService.updatePrinterSettings(autoPrintKOT: val);
      await ref.read(authProvider.notifier).loadSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(val ? 'Auto Print KOT enabled' : 'Auto Print KOT disabled'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Rollback on failure
      if (mounted) {
        setState(() => _autoPrintKOT = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingAutoKOT = false);
    }
  }

  Future<void> _toggleAutoPrintBill(bool val) async {
    final previous = _autoPrintBill;
    setState(() {
      _autoPrintBill = val;
      _isSavingAutoBill = true;
    });

    try {
      final kotService = ref.read(kotPrintServiceProvider);
      await kotService.updatePrinterSettings(autoPrintBill: val);
      await ref.read(authProvider.notifier).loadSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(val ? 'Auto Print Bill enabled' : 'Auto Print Bill disabled'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Rollback on failure
      if (mounted) {
        setState(() => _autoPrintBill = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingAutoBill = false);
    }
  }

  Future<void> _detectPrinters() async {
    setState(() {
      _isDetectingPrinters = true;
      _printerError = null;
    });

    try {
      final kotService = ref.read(kotPrintServiceProvider);
      final printers = await kotService.getPrinters();
      if (mounted) {
        setState(() {
          _availablePrinters = printers;
          if (printers.isEmpty) {
            _printerError = "No printers found. Ensure PrintNode client is running.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _printerError = "Failed to detect printers: $e";
        });
      }
    } finally {
      if (mounted) setState(() => _isDetectingPrinters = false);
    }
  }

  Future<void> _selectPrinter(int printerId) async {
    final previous = _selectedPrinterId;
    setState(() {
      _selectedPrinterId = printerId;
      _isSavingPrinterId = true;
    });

    try {
      final kotService = ref.read(kotPrintServiceProvider);
      await kotService.updatePrinterSettings(printNodePrinterId: printerId);
      await ref.read(authProvider.notifier).loadSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer linked successfully'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _selectedPrinterId = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to link printer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPrinterId = false);
    }
  }

  Future<void> _scanBluetoothPrinters() async {
    final btService = ref.read(bluetoothPrinterServiceProvider);

    // 1. Request Bluetooth runtime permissions (critical on Android 12+)
    final hasPermission = await btService.requestBluetoothPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Nearby devices & Bluetooth permission is required to detect thermal printers.',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => btService.openSettings(),
            ),
          ),
        );
      }
      return;
    }

    // 2. Check if Bluetooth is turned ON
    final enabled = await btService.isBluetoothEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Bluetooth on your device first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isBtScanning = true);
    try {
      final devices = await btService.getPairedDevices();
      if (mounted) {
        setState(() => _pairedBtDevices = devices);
        if (devices.isEmpty) {
          _showPairingHelpDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Found ${devices.length} paired Bluetooth device(s).'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning Bluetooth: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBtScanning = false);
    }
  }

  void _showPairingHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(LucideIcons.printer, color: const Color(0xFF2563EB), size: 20.sp),
            ),
            SizedBox(width: 10.w),
            const Expanded(
              child: Text(
                'How to Pair Your Printer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thermal printers must be paired in your phone\'s system Bluetooth settings first:',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            SizedBox(height: 12.h),
            _buildHelpStep('1', 'Turn on your thermal printer (e.g. CPENSUS, POS-58).'),
            _buildHelpStep('2', 'Open phone Settings > Bluetooth / Connected devices.'),
            _buildHelpStep('3', 'Tap "Pair new device" and select your printer.'),
            _buildHelpStep('4', 'Enter PIN if prompted (usually 0000 or 1234).'),
            _buildHelpStep('5', 'Return to ScanServe and tap "Scan Bluetooth".'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20.r,
            height: 20.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2563EB),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectBluetoothPrinter(BluetoothInfo device) async {
    setState(() => _isBtConnecting = true);
    try {
      final btService = ref.read(bluetoothPrinterServiceProvider);
      final ok = await btService.connect(
        device.macAdress,
        printerName: device.name.isNotEmpty ? device.name : 'Thermal Printer',
      );
      if (ok) {
        await _initBluetoothSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to ${device.name.isNotEmpty ? device.name : device.macAdress}! Direct printing is ready.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not connect to ${device.name}. Ensure printer is turned on and in range.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBtConnecting = false);
    }
  }

  Future<void> _disconnectBluetoothPrinter() async {
    final btService = ref.read(bluetoothPrinterServiceProvider);
    await btService.clearSavedPrinter();
    await _initBluetoothSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected Bluetooth printer.'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  Future<void> _printTestTicket() async {
    setState(() => _isPrintingTest = true);
    try {
      final btService = ref.read(bluetoothPrinterServiceProvider);
      final ok = await btService.printTestTicket();
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Test ticket printed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to print test ticket. Check printer connection.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrintingTest = false);
    }
  }

  Future<void> _setPaperSize(String size) async {
    final btService = ref.read(bluetoothPrinterServiceProvider);
    await btService.setPaperSize(size);
    setState(() => _savedPaperSize = size);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth changes and keep settings in sync if updated externally
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.user != null) {
        final data = (next.user!['data'] is Map) ? next.user!['data'] : next.user!;
        setState(() {
          _liveOrderKOT = data['liveOrderKOT'] == true;
          _autoPrintKOT = data['autoPrintKOT'] == true;
          _autoPrintBill = data['autoPrintBill'] == true;
          if (data['printNodePrinterId'] != null) {
            _selectedPrinterId = int.tryParse(data['printNodePrinterId'].toString());
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5ED),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Icon(
                        LucideIcons.settings,
                        color: const Color(0xFFFF5C00),
                        size: 26.sp,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Printer & KOT Settings',
                            style: TextStyle(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            'Configure automatic ticket printing and connect hardware',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),

                // KOT TOGGLES CARD
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24.r),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(5),
                        blurRadius: 16.r,
                        offset: Offset(0, 4.h),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // TOGGLE 1: Live Order KOT
                      _buildToggleTile(
                        icon: LucideIcons.zap,
                        iconColor: const Color(0xFF8B5CF6),
                        iconBg: const Color(0xFFF5F3FF),
                        title: 'Live Order KOT',
                        subtitle: 'Instantly auto-prints — no button click needed',
                        value: _liveOrderKOT,
                        activeColor: const Color(0xFF8B5CF6),
                        isLoading: _isSavingLiveOrder,
                        onChanged: _toggleLiveOrderKOT,
                      ),
                      Divider(height: 1, color: Colors.grey.shade100),

                      // TOGGLE 2: Auto Print KOT
                      _buildToggleTile(
                        icon: LucideIcons.printer,
                        iconColor: const Color(0xFF10B981),
                        iconBg: const Color(0xFFECFDF5),
                        title: 'Auto Print KOT',
                        subtitle: _liveOrderKOT
                            ? 'Disabled while Live Order KOT is on'
                            : 'Shows a Print KOT button on every order',
                        value: _autoPrintKOT,
                        activeColor: const Color(0xFF10B981),
                        isDisabled: _liveOrderKOT,
                        isLoading: _isSavingAutoKOT,
                        onChanged: _liveOrderKOT ? null : _toggleAutoPrintKOT,
                      ),
                      Divider(height: 1, color: Colors.grey.shade100),

                      // TOGGLE 3: Auto Print Bill
                      _buildToggleTile(
                        icon: LucideIcons.receipt,
                        iconColor: const Color(0xFF10B981),
                        iconBg: const Color(0xFFECFDF5),
                        title: 'Auto Print Bill',
                        subtitle: 'Customer receipt on checkout',
                        value: _autoPrintBill,
                        activeColor: const Color(0xFF10B981),
                        isLoading: _isSavingAutoBill,
                        onChanged: _toggleAutoPrintBill,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 28.h),

                // DIRECT BLUETOOTH THERMAL PRINTER CARD
                _buildBluetoothPrinterCard(),
                SizedBox(height: 28.h),

                // PRINTER DETECTION SECTION
                Container(
                  padding: EdgeInsets.all(20.r),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24.r),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(5),
                        blurRadius: 16.r,
                        offset: Offset(0, 4.h),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 480;

                      Widget printNodeHeaderInfo = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.r),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              LucideIcons.printerCheck,
                              color: const Color(0xFF2563EB),
                              size: 20.sp,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Printer Hardware Connection',
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  'Discover CPENSUS / PrintNode wireless & USB printers',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      Widget detectBtn = ElevatedButton.icon(
                        onPressed: _isDetectingPrinters ? null : _detectPrinters,
                        icon: _isDetectingPrinters
                            ? SizedBox(
                                width: 14.r,
                                height: 14.r,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(LucideIcons.scan, size: 16.sp),
                        label: Text(
                          _isDetectingPrinters ? 'Detecting...' : 'Detect Printers',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.sp,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 11.h,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                        ),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isCompact) ...[
                            printNodeHeaderInfo,
                            SizedBox(height: 12.h),
                            SizedBox(
                              width: double.infinity,
                              child: detectBtn,
                            ),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: printNodeHeaderInfo),
                                SizedBox(width: 12.w),
                                detectBtn,
                              ],
                            ),
                          ],
                          SizedBox(height: 18.h),

                          if (_printerError != null)
                            Container(
                              padding: EdgeInsets.all(12.r),
                              margin: EdgeInsets.only(bottom: 16.h),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    LucideIcons.info,
                                    color: Colors.amber.shade800,
                                    size: 18.sp,
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Text(
                                      _printerError!,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.amber.shade900,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (_availablePrinters.isEmpty && !_isDetectingPrinters)
                            Container(
                              padding: EdgeInsets.symmetric(vertical: 20.h),
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  Icon(
                                    LucideIcons.hardDriveDownload,
                                    color: Colors.grey.shade400,
                                    size: 32.sp,
                                  ),
                                  SizedBox(height: 8.h),
                                  Text(
                                    'Tap "Detect Printers" to list active printers from backend',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            Text(
                              'SELECT TARGET PRINTER',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Wrap(
                              spacing: 10.w,
                              runSpacing: 10.h,
                              children: _availablePrinters.map((p) {
                                final pId = int.tryParse(p['id']?.toString() ?? '');
                                final pName = p['name']?.toString() ?? 'Printer';
                                final isSelected = pId != null && pId == _selectedPrinterId;

                                return InkWell(
                                  onTap: (pId != null && !_isSavingPrinterId)
                                      ? () => _selectPrinter(pId)
                                      : null,
                                  borderRadius: BorderRadius.circular(16.r),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14.w,
                                      vertical: 12.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFF0FDF4)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16.r),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF10B981)
                                            : Colors.grey.shade200,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isSelected
                                              ? LucideIcons.checkCircle
                                              : LucideIcons.printer,
                                          size: 18.sp,
                                          color: isSelected
                                              ? const Color(0xFF10B981)
                                              : Colors.grey.shade600,
                                        ),
                                        SizedBox(width: 8.w),
                                        Flexible(
                                          child: Text(
                                            pName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.sp,
                                              fontWeight: isSelected
                                                  ? FontWeight.w900
                                                  : FontWeight.bold,
                                              color: isSelected
                                                  ? const Color(0xFF065F46)
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          SizedBox(width: 8.w),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6.w,
                                              vertical: 2.h,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981),
                                              borderRadius: BorderRadius.circular(6.r),
                                            ),
                                            child: Text(
                                              'ACTIVE',
                                              style: TextStyle(
                                                fontSize: 9.sp,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool>? onChanged,
    bool isDisabled = false,
    bool isLoading = false,
  }) {
    final effectiveTextColor = isDisabled ? Colors.grey.shade400 : const Color(0xFF0F172A);
    final effectiveSubColor = isDisabled ? Colors.grey.shade400 : const Color(0xFF64748B);

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: isDisabled ? Colors.grey.shade100 : iconBg,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Icon(
                icon,
                color: isDisabled ? Colors.grey.shade400 : iconColor,
                size: 22.sp,
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w800,
                      color: effectiveTextColor,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: effectiveSubColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            if (isLoading)
              SizedBox(
                width: 24.r,
                height: 24.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: activeColor,
                ),
              )
            else
              Switch(
                value: value,
                activeThumbColor: activeColor,
                onChanged: isDisabled ? null : onChanged,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothPrinterCard() {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 480;

          Widget headerInfo = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  LucideIcons.bluetooth,
                  color: const Color(0xFF2563EB),
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.w,
                      runSpacing: 4.h,
                      children: [
                        Text(
                          'Direct Bluetooth Thermal Printer',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'ZERO 3RD PARTY',
                            style: TextStyle(
                              fontSize: 9.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Direct wireless print to CPENSUS POS-58 or any ESC/POS thermal printer',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          Widget scanBtn = ElevatedButton.icon(
            onPressed: _isBtScanning ? null : _scanBluetoothPrinters,
            icon: _isBtScanning
                ? SizedBox(
                    width: 14.r,
                    height: 14.r,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(LucideIcons.scan, size: 16.sp),
            label: Text(
              _isBtScanning ? 'Scanning...' : 'Scan Bluetooth',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.sp,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 11.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              if (isCompact) ...[
                headerInfo,
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  child: scanBtn,
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headerInfo),
                    SizedBox(width: 12.w),
                    scanBtn,
                  ],
                ),
              ],
              SizedBox(height: 18.h),

              // Current Connection Banner
              if (_savedBtMac.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(14.r),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, bannerConstraints) {
                      final isNarrowBanner = bannerConstraints.maxWidth < 440;

                      Widget printerInfo = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.all(8.r),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDCFCE7),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.printer,
                              color: const Color(0xFF16A34A),
                              size: 18.sp,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6.w,
                                  runSpacing: 4.h,
                                  children: [
                                    Text(
                                      _savedBtName.isNotEmpty ? _savedBtName : 'CPENSUS Thermal Printer',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF14532D),
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF16A34A),
                                        borderRadius: BorderRadius.circular(4.r),
                                      ),
                                      child: Text(
                                        _isBtConnected ? 'CONNECTED' : 'ACTIVE',
                                        style: const TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  'MAC: $_savedBtMac • ${_savedPaperSize}mm Roll',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: const Color(0xFF15803D),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      Widget actions = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isPrintingTest ? null : _printTestTicket,
                            icon: _isPrintingTest
                                ? SizedBox(
                                    width: 12.r,
                                    height: 12.r,
                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(LucideIcons.fileText, size: 14.sp),
                            label: Text(
                              _isPrintingTest ? 'Printing...' : 'Test Print',
                              style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF16A34A),
                              side: const BorderSide(color: Color(0xFF86EFAC)),
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          IconButton(
                            tooltip: 'Disconnect Printer',
                            icon: Icon(LucideIcons.trash2, color: Colors.red.shade400, size: 18.sp),
                            onPressed: _disconnectBluetoothPrinter,
                          ),
                        ],
                      );

                      if (isNarrowBanner) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            printerInfo,
                            SizedBox(height: 10.h),
                            Align(
                              alignment: Alignment.centerRight,
                              child: actions,
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(child: printerInfo),
                            SizedBox(width: 8.w),
                            actions,
                          ],
                        );
                      }
                    },
                  ),
                )
              else
                Container(
                  padding: EdgeInsets.all(14.r),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.bluetoothSearching, color: const Color(0xFF94A3B8), size: 20.sp),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No Bluetooth thermal printer selected. Tap "Scan Bluetooth" to discover paired printers (e.g. CPENSUS).',
                              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF64748B)),
                            ),
                            SizedBox(height: 4.h),
                            GestureDetector(
                              onTap: _showPairingHelpDialog,
                              child: Text(
                                'First time setting up? Tap for pairing guide',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: const Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 16.h),

              // Paper Size Selector
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10.w,
                runSpacing: 8.h,
                children: [
                  Text(
                    'Paper Roll Width:',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  ChoiceChip(
                    label: Text('58mm (CPENSUS)', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)),
                    selected: _savedPaperSize == '58',
                    selectedColor: const Color(0xFFDBEAFE),
                    onSelected: (val) {
                      if (val) _setPaperSize('58');
                    },
                  ),
                  ChoiceChip(
                    label: Text('80mm (Wide)', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)),
                    selected: _savedPaperSize == '80',
                    selectedColor: const Color(0xFFDBEAFE),
                    onSelected: (val) {
                      if (val) _setPaperSize('80');
                    },
                  ),
                ],
              ),

              // Paired Devices List
              if (_pairedBtDevices.isNotEmpty) ...[
                SizedBox(height: 20.h),
                Divider(color: Colors.grey.shade100),
                SizedBox(height: 8.h),
                Text(
                  'Paired Bluetooth Devices (${_pairedBtDevices.length})',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 12.h),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pairedBtDevices.length,
                  separatorBuilder: (context, index) => SizedBox(height: 8.h),
                  itemBuilder: (context, idx) {
                    final device = _pairedBtDevices[idx];
                    final isSelected = device.macAdress == _savedBtMac;
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.printer,
                                  size: 18.sp,
                                  color: isSelected ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.name.isNotEmpty ? device.name : 'Unknown Device',
                                        style: TextStyle(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        device.macAdress,
                                        style: TextStyle(fontSize: 11.sp, color: const Color(0xFF94A3B8)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 10.w),
                          if (isSelected)
                            Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF16A34A),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: _isBtConnecting ? null : () => _connectBluetoothPrinter(device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                              ),
                              child: Text(
                                'Connect',
                                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
