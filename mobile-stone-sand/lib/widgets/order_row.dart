import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../logic/order_status.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final pay = paymentBadge(o);
    final del = deliveryBadge(o);
    return InkWell(
      onTap: () => openOrder(context, o.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: o.cancelled ? AppColors.subtle : AppColors.primarySoft,
              ),
              child: Icon(
                o.fulfillment == Fulfillment.delivery ? Icons.local_shipping_outlined : Icons.storefront_outlined,
                size: 18,
                color: o.cancelled ? AppColors.muted : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: o.cancelled ? AppColors.muted : AppColors.ink,
                            decoration: o.cancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMoney(o.total),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFeatures: tabular),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${o.orderNo} · ${formatDateShort(o.orderDate)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                      ),
                      SourceBadge(o.source),
                      if (o.demo) const DemoBadge(),
                      if (o.cancelled)
                        const AppBadge('ยกเลิก', tone: BadgeTone.danger)
                      else ...[
                        AppBadge(pay.label, tone: pay.tone),
                        AppBadge(del.label, tone: del.tone),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Orders in a bordered card with dividers.
class OrderList extends StatelessWidget {
  const OrderList({super.key, required this.orders, this.header});
  final List<Order> orders;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          ?header,
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0 || header != null) const Divider(height: 1),
            OrderRow(order: orders[i]),
          ],
        ],
      ),
    );
  }
}
