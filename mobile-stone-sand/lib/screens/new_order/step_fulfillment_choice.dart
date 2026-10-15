import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

class StepFulfillmentChoice extends StatelessWidget {
  const StepFulfillmentChoice({super.key, required this.fulfillment, required this.onSelect});
  final Fulfillment? fulfillment;
  final ValueChanged<Fulfillment> onSelect;

  @override
  Widget build(BuildContext context) {
    final note = switch (fulfillment) {
      Fulfillment.pickup => (Icons.place_outlined, 'ลูกค้ามารับที่ท่าทราย ไม่มีค่าส่ง ระบบจะบันทึกสถานะการส่งเป็น "มารับเอง"'),
      Fulfillment.delivery => (
          Icons.local_shipping_outlined,
          'เลือกสินค้าและลูกค้าก่อน แล้วค่อยปักหมุด เลือกตำบล รถ และคนขับ ในขั้น "จัดส่ง"',
        ),
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          'การรับสินค้า',
          subtitle: 'ลูกค้ามารับเองที่ท่าทราย หรือให้รถไปส่ง ราคาสินค้าจะคิดตามที่เลือก',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ChoiceCard(
                active: fulfillment == Fulfillment.pickup,
                onTap: () => onSelect(Fulfillment.pickup),
                icon: Icons.storefront_outlined,
                title: 'มารับเอง',
                hint: 'ราคามารับเอง ไม่มีค่าส่ง',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceCard(
                active: fulfillment == Fulfillment.delivery,
                onTap: () => onSelect(Fulfillment.delivery),
                icon: Icons.local_shipping_outlined,
                title: 'จัดส่ง',
                hint: 'ในเขต อ.วังเหนือ',
              ),
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(note.$1, size: 18, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(note.$2, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
