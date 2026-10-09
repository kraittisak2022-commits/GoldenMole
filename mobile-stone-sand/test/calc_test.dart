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
    test('uses the lowest fee within 3 km of the main road', () {
      expect(suggestDeliveryFee(300, 400, 0), 300);
      expect(suggestDeliveryFee(300, 400, 2.4), 300);
      expect(suggestDeliveryFee(300, 400, 3), 300);
    });

    test('scales between 3 km and maxKm, rounded up to 50', () {
      expect(suggestDeliveryFee(300, 400, 4), 350);
      expect(suggestDeliveryFee(300, 400, 6.5), 350);
      expect(suggestDeliveryFee(300, 400, 7), 400);
      expect(suggestDeliveryFee(1200, 1500, 6.5), 1350);
    });

    test('uses the highest fee at or beyond maxKm', () {
      expect(suggestDeliveryFee(300, 400, 10), 400);
      expect(suggestDeliveryFee(1200, 1500, 25), 1500);
    });

    test('falls back to the lowest fee without a distance', () {
      expect(suggestDeliveryFee(300, 400, null), 300);
      expect(suggestDeliveryFee(300, 400, double.nan), 300);
    });

    test('respects custom settings', () {
      expect(suggestDeliveryFee(1200, 1500, 5, const DeliverySettings(nearKm: 2, maxKm: 8, roundTo: 100)), 1400);
      expect(suggestDeliveryFee(1200, 1500, 5, const DeliverySettings(nearKm: 2, maxKm: 8, roundTo: 0)), 1350);
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
