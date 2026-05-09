import 'package:flutter/material.dart';

/// ตัวย่อ + สีแบรนด์โดยประมาณสำหรับแสดงใน dropdown ธนาคาร (ไม่ใช่โลโก้ทางการ)
class ThaiBankBrandSpec {
  const ThaiBankBrandSpec({
    required this.code,
    required this.background,
    this.foreground = Colors.white,
  });

  final String code;
  final Color background;
  final Color foreground;
}

ThaiBankBrandSpec? thaiBankBrandSpecForName(String bankName) {
  final key = bankName.trim();
  const map = <String, ThaiBankBrandSpec>{
    'ธนาคารกรุงเทพ': ThaiBankBrandSpec(
      code: 'BBL',
      background: Color(0xFF1E4598),
    ),
    'ธนาคารกสิกรไทย': ThaiBankBrandSpec(
      code: 'KBANK',
      background: Color(0xFF138F2D),
    ),
    'ธนาคารไทยพาณิชย์': ThaiBankBrandSpec(
      code: 'SCB',
      background: Color(0xFF4E2A7E),
    ),
    'ธนาคารกรุงไทย': ThaiBankBrandSpec(
      code: 'KTB',
      background: Color(0xFF1BA4E8),
    ),
    'ธนาคารกรุงศรีอยุธยา': ThaiBankBrandSpec(
      code: 'BAY',
      background: Color(0xFFE87722),
      foreground: Color(0xFF1A1A1A),
    ),
    'ธนาคารทหารไทยธนชาต': ThaiBankBrandSpec(
      code: 'TTB',
      background: Color(0xFF004FF8),
    ),
    'ธนาคารไอซีบีซี (ไทย)': ThaiBankBrandSpec(
      code: 'ICBC',
      background: Color(0xFFC41E3A),
    ),
    'ธนาคารยูโอบี': ThaiBankBrandSpec(
      code: 'UOB',
      background: Color(0xFF003B79),
    ),
    'ธนาคารซีไอเอ็มบี ไทย': ThaiBankBrandSpec(
      code: 'CIMB',
      background: Color(0xFF790000),
    ),
    'ธนาคารธนชาต': ThaiBankBrandSpec(
      code: 'TBNK',
      background: Color(0xFF1C3F94),
    ),
    'ธนาคารเกียรตินาคินภัทร': ThaiBankBrandSpec(
      code: 'KKP',
      background: Color(0xFF199CC5),
    ),
    'ธนาคารออมสิน': ThaiBankBrandSpec(
      code: 'GSB',
      background: Color(0xFFE91A1A),
    ),
    'ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร': ThaiBankBrandSpec(
      code: 'BAAC',
      background: Color(0xFF4B9B1E),
    ),
    'ธนาคารอาคารสงเคราะห์': ThaiBankBrandSpec(
      code: 'GHB',
      background: Color(0xFFFF8C00),
      foreground: Color(0xFF1A1A1A),
    ),
    'ธนาคารแลนด์ แอนด์ เฮ้าส์': ThaiBankBrandSpec(
      code: 'LH',
      background: Color(0xFF6B2D5C),
    ),
    'ธนาคารซูมิโตโม มิตซุย ทรัสต์ (ไทย)': ThaiBankBrandSpec(
      code: 'SMTB',
      background: Color(0xFF004097),
    ),
    'ธนาคารฮ่องกงและเซี่ยงไฮ้แบงกิ้งคอร์ปอเรชั่น จำกัด': ThaiBankBrandSpec(
      code: 'HSBC',
      background: Color(0xFFDB0011),
    ),
  };
  return map[key];
}

/// ไอคอนแบบชิปตัวย่อธนาคาร — ใช้คู่กับชื่อเต็มใน dropdown
class ThaiBankBrandIcon extends StatelessWidget {
  const ThaiBankBrandIcon({
    super.key,
    required this.bankName,
    this.size = 26,
  });

  final String bankName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = thaiBankBrandSpecForName(bankName);
    if (spec == null) {
      return Icon(
        Icons.account_balance_outlined,
        size: size * 0.85,
        color: const Color(0xFF5B6D83),
      );
    }
    final fontSize = spec.code.length <= 3 ? 9.0 : 7.5;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: spec.background.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            spec.code,
            maxLines: 1,
            style: TextStyle(
              color: spec.foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
