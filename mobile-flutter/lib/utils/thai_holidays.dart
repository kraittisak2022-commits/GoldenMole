class ThaiHoliday {
  const ThaiHoliday({required this.id, required this.date, required this.name});

  final String id;
  final String date;
  final String name;
}

List<ThaiHoliday> getThaiPublicHolidays(int year) {
  const rows = [
    {'md': '01-01', 'name': 'วันขึ้นปีใหม่'},
    {'md': '02-12', 'name': 'วันมาฆบูชา'},
    {'md': '04-06', 'name': 'วันจักรี'},
    {'md': '04-13', 'name': 'วันสงกรานต์'},
    {'md': '04-14', 'name': 'วันสงกรานต์'},
    {'md': '04-15', 'name': 'วันสงกรานต์'},
    {'md': '05-01', 'name': 'วันแรงงานแห่งชาติ'},
    {'md': '05-04', 'name': 'วันฉัตรมงคล'},
    {'md': '05-11', 'name': 'วันพืชมงคล (ประมาณการ)'},
    {'md': '06-03', 'name': 'วันเฉลิมพระชนมพรรษา สมเด็จพระราชินี'},
    {'md': '07-10', 'name': 'วันอาสาฬหบูชา (ประมาณการ)'},
    {'md': '07-11', 'name': 'วันเข้าพรรษา (ประมาณการ)'},
    {'md': '07-28', 'name': 'วันเฉลิมพระชนมพรรษา ร.10'},
    {'md': '08-12', 'name': 'วันแม่แห่งชาติ'},
    {'md': '10-13', 'name': 'วันนวมินทรมหาราช'},
    {'md': '10-23', 'name': 'วันปิยมหาราช'},
    {'md': '12-05', 'name': 'วันพ่อแห่งชาติ'},
    {'md': '12-10', 'name': 'วันรัฐธรรมนูญ'},
    {'md': '12-31', 'name': 'วันสิ้นปี'},
  ];

  return rows.map((row) {
    final md = row['md']!;
    return ThaiHoliday(
      id: 'holiday_${year}_$md',
      date: '$year-$md',
      name: row['name']!,
    );
  }).toList();
}

Map<String, ThaiHoliday> getThaiPublicHolidayMap(int year) {
  return {for (final h in getThaiPublicHolidays(year)) h.date: h};
}
