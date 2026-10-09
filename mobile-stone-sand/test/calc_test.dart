import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/calc/baht_text.dart';
import 'package:mobile_stone_sand/calc/delivery_fee.dart';
import 'package:mobile_stone_sand/calc/pricing.dart';
import 'package:mobile_stone_sand/calc/trips.dart';

TotalsInput input({
  List<PriceLine>? items,
  num feePerTrip = 350,
  num trips = 2,
  num remoteSurcharge = 0,
  num deliveryDiscount = 0,
  DiscountType discountType = DiscountType.baht,
  num discountValue = 0,
}) =>
    TotalsInput(
      items: items ??
          const [
            PriceLine(unitPrice: 400, quantity: 5),
            PriceLine(unitPrice: 220, quantity: 5),
          ],
      feePerTrip: feePerTrip,
      trips: trips,
      remoteSurcharge: remoteSurcharge,
      deliveryDiscount: deliveryDiscount,
      discountType: discountType,
      discountValue: discountValue,
    );

void main() {
  group('lineAmount', () {
    test('matches the price list for 1, 3 and 5 คิว', () {
      expect(lineAmount(400, 1), 400);
      expect(lineAmount(400, 3), 1200);
      expect(lineAmount(400, 5), 2000);
      expect(lineAmount(300, 5), 1500);
      expect(lineAmount(220, 3), 660);
      expect(lineAmount(220, 5), 1100);
    });

    test('handles fractional quantities and invalid input', () {
      expect(lineAmount(220, 1.5), 330);
      expect(lineAmount(400, 0), 0);
      expect(lineAmount(400, -2), 0);
    });
  });

  group('computeTotals', () {
    test('adds products and delivery per trip', () {
      final t = computeTotals(input());
      expect(t.subtotal, 3100);
      expect(t.deliveryTotal, 700);
      expect(t.itemDiscount, 0);
      expect(t.deliveryDiscount, 0);
      expect(t.billDiscount, 0);
      expect(t.discountAmount, 0);
      expect(t.total, 3800);
      expect(t.totalQuantity, 10);
    });

    test('adds the remote surcharge once', () {
      expect(computeTotals(input(remoteSurcharge: 200)).deliveryTotal, 900);
    });

    test('applies a baht discount', () {
      final t = computeTotals(input(discountValue: 100));
      expect(t.discountAmount, 100);
      expect(t.total, 3700);
    });

    test('applies a percent discount to products only', () {
      final t = computeTotals(input(discountType: DiscountType.percent, discountValue: 10));
      expect(t.discountAmount, 310);
      expect(t.total, 3490);
    });

    test('never goes below zero', () {
      expect(computeTotals(input(discountValue: 99999)).total, 0);
      expect(
        computeTotals(input(discountType: DiscountType.percent, discountValue: 500)).discountAmount,
        3100,
      );
    });

    test('pickup orders have no delivery', () {
      expect(computeTotals(input(feePerTrip: 0, trips: 0)).total, 3100);
    });

    test('takes a per-คิว discount off each product separately', () {
      final t = computeTotals(input(items: const [
        PriceLine(unitPrice: 400, quantity: 5, discountPerUnit: 30),
        PriceLine(unitPrice: 220, quantity: 5, discountPerUnit: 20),
      ]));
      expect(t.subtotal, 3100);
      expect(t.itemDiscount, 250);
      expect(t.discountAmount, 250);
      expect(t.total, 3550);
    });

    test('stacks the bill discount on top; percent uses the discounted products', () {
      const items = [PriceLine(unitPrice: 400, quantity: 5, discountPerUnit: 40)];
      expect(computeTotals(input(items: items, discountValue: 100)).discountAmount, 300);
      expect(
        computeTotals(input(items: items, discountType: DiscountType.percent, discountValue: 10)).discountAmount,
        380,
      );
    });

    test('takes ส่วนลดค่าส่ง off the delivery fee, never more than the fee', () {
      final t = computeTotals(input(deliveryDiscount: 100));
      expect(t.deliveryTotal, 700);
      expect(t.deliveryDiscount, 100);
      expect(t.discountAmount, 100);
      expect(t.total, 3700);
      expect(computeTotals(input(deliveryDiscount: 5000)).deliveryDiscount, 700);
      expect(computeTotals(input(feePerTrip: 0, trips: 0, deliveryDiscount: 100)).deliveryDiscount, 0);
    });

    test('keeps the bill discount separate from ส่วนลดค่าส่ง', () {
      final t = computeTotals(
        input(deliveryDiscount: 100, discountType: DiscountType.percent, discountValue: 10),
      );
      expect(t.billDiscount, 310);
      expect(t.discountAmount, 410);
      expect(t.total, 3390);
    });
  });

  group('lineDiscount', () {
    test('never discounts more than the unit price', () {
      expect(lineDiscount(220, 5, 20), 100);
      expect(lineDiscount(220, 5, 999), 1100);
      expect(lineDiscount(220, 0, 20), 0);
      expect(lineDiscount(220, 5), 0);
    });
  });

  group('trips', () {
    test('suggests a 3 คิว truck for small loads', () {
      expect(suggestTruckSize(1), 3);
      expect(suggestTruckSize(3), 3);
      expect(suggestTruckSize(4), 5);
      expect(suggestTruckSize(12), 5);
    });

    test('counts the trips the customer asked for', () {
      expect(totalTrips([]), 0);
      expect(totalTrips([const Load(perTrip: 3, trips: 2)]), 2);
      expect(totalTrips([const Load(perTrip: 3, trips: 2), const Load(perTrip: 5, trips: 1)]), 3);
      expect(totalTrips([const Load(perTrip: 0, trips: 2), const Load(perTrip: 3, trips: 0)]), 0);
    });

    test('picks the smallest truck that carries the largest load per trip', () {
      expect(truckForLoads([const Load(perTrip: 1, trips: 4), const Load(perTrip: 3, trips: 1)]), 3);
      expect(truckForLoads([const Load(perTrip: 3, trips: 1), const Load(perTrip: 5, trips: 1)]), 5);
    });

    test('rejects a truck smaller than a load per trip', () {
      expect(truckFits(3, [const Load(perTrip: 3, trips: 2)]), true);
      expect(truckFits(5, [const Load(perTrip: 3, trips: 2)]), true);
      expect(truckFits(3, [const Load(perTrip: 4, trips: 1)]), false);
      expect(truckFits(3, [const Load(perTrip: 5, trips: 0)]), true);
    });
  });

  group('suggestDeliveryFee', () {
    const delivery = DeliverySettings(nearKm: 1, driverPerKm5: 50, driverPerKm3: 30);

    test('is the tambon fee within the free first km', () {
      expect(suggestDeliveryFee(240, 0, 5, delivery), 240);
      expect(suggestDeliveryFee(240, 1, 3, delivery), 240);
    });

    test('adds the truck size baht/km for every started km beyond the first', () {
      expect(suggestDeliveryFee(240, 1.4, 5, delivery), 290); // 0.4 km → 1 km × 50
      expect(suggestDeliveryFee(240, 1.7, 3, delivery), 270); // 0.7 km → 1 km × 30
      expect(suggestDeliveryFee(240, 2.4, 5, delivery), 340); // 1.4 km → 2 km × 50
      expect(suggestDeliveryFee(240, 2, 5, delivery), 290);
    });

    test('uses the 5-คิว rate when the truck size is unknown', () {
      expect(suggestDeliveryFee(240, 2.4, null, delivery), 340);
    });

    test('falls back to the tambon fee without a distance or a rate', () {
      expect(suggestDeliveryFee(240, null, 5, delivery), 240);
      expect(suggestDeliveryFee(240, double.nan, 5, delivery), 240);
      expect(suggestDeliveryFee(240, 5, 3, delivery.copyWith(driverPerKm3: 0)), 240);
    });

    test('counts whole km despite floating-point error', () {
      expect(chargedKm(1.3, 0.3), 1);
      expect(chargedKm(3.3, 1.1), 3);
    });

    test('keeps other stored keys and drops the old range settings when saving', () {
      final saved = DeliverySettings.fromJson(
        {'nearKm': 1, 'driverPerKm5': 50, 'driverPerKm3': 40, 'maxKm': 10, 'roundTo': 50, 'other': true},
      ).copyWith(nearKm: 2).toJson();
      expect(saved, {'other': true, 'nearKm': 2, 'driverPerKm5': 50, 'driverPerKm3': 40});
    });
  });

  group('bahtText', () {
    const cases = <num, String>{
      0: 'ศูนย์บาทถ้วน',
      1: 'หนึ่งบาทถ้วน',
      11: 'สิบเอ็ดบาทถ้วน',
      21: 'ยี่สิบเอ็ดบาทถ้วน',
      101: 'หนึ่งร้อยเอ็ดบาทถ้วน',
      220: 'สองร้อยยี่สิบบาทถ้วน',
      1500: 'หนึ่งพันห้าร้อยบาทถ้วน',
      11875: 'หนึ่งหมื่นหนึ่งพันแปดร้อยเจ็ดสิบห้าบาทถ้วน',
      1000000: 'หนึ่งล้านบาทถ้วน',
      1000001: 'หนึ่งล้านเอ็ดบาทถ้วน',
      21500000: 'ยี่สิบเอ็ดล้านห้าแสนบาทถ้วน',
    };
    cases.forEach((n, text) {
      test('$n → $text', () => expect(bahtText(n), text));
    });

    test('reads satang', () {
      expect(bahtText(776.87), 'เจ็ดร้อยเจ็ดสิบหกบาทแปดสิบเจ็ดสตางค์');
      expect(bahtText(0.5), 'ห้าสิบสตางค์');
      expect(bahtText(10.01), 'สิบบาทหนึ่งสตางค์');
    });
  });
}
