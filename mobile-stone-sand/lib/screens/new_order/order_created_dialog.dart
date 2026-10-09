import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/catalog_scope.dart';
import '../../logic/driver_pay.dart' show driverTripRate;
import '../../logic/order_status.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

/// Shown after a delivery order is saved: send the job to the driver, then open the bill.
/// Completes when the user chooses "ออกบิล" (or dismisses the dialog).
Future<void> showOrderCreatedDialog(BuildContext context, Order order) {
  final catalog = CatalogScope.read(context);
  final zone = catalog.zoneById(order.zoneId);
  final pay = order.driverWage > 0
      ? order.driverWage
      : driverTripRate(zone, order.truckSize, order.roadDistanceKm, catalog.settings.delivery).perTrip * order.trips;
  final message = driverMessage(order, zone, catalog.driverById(order.driverId), pay);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OrderCreatedDialog(order: order, message: message),
  );
}

class _OrderCreatedDialog extends StatefulWidget {
  const _OrderCreatedDialog({required this.order, required this.message});

  final Order order;
  final String message;

  @override
  State<_OrderCreatedDialog> createState() => _OrderCreatedDialogState();
}

class _OrderCreatedDialogState extends State<_OrderCreatedDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('บันทึกออเดอร์ ${widget.order.orderNo} แล้ว'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'คัดลอกข้อความไปวางใน LINE ส่งคนขับ แล้วออกบิลให้ลูกค้า',
              style: TextStyle(color: AppColors.success, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Text(widget.message, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                label: Text(_copied ? 'คัดลอกแล้ว' : 'คัดลอกข้อความส่งคนขับ'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('ออกบิล'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
