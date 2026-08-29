import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

export type ShareLocale = 'th' | 'zh';
export type ShareTheme = 'light' | 'dark';

const LOCALE_KEY = 'cm_share_locale_v1';
const THEME_KEY = 'cm_share_theme_v1';

const messages = {
    th: {
        langShort: 'TH',
        langToggle: '中文',
        themeLight: 'โหมดสว่าง',
        themeDark: 'โหมดมืด',
        loading: 'กำลังโหลด...',
        cannotOpenDashboard: 'ไม่สามารถเปิดแดชบอร์ดได้',
        shareNotFound: 'ไม่พบการตั้งค่าการแชร์',
        shareDisabled: 'การแชร์ลิงก์ถูกปิดอยู่',
        invalidLink: 'ลิงก์ไม่ถูกต้องหรือหมดอายุ',
        pinNotSet: 'ยังไม่ได้ตั้งรหัส PIN',
        realtimeBanner: 'โหมดดูแบบ Real-time — อัปเดตอัตโนมัติ',
        pinTitle: 'แดชบอร์ด Real-time',
        pinSubtitle: 'กรอกรหัส PIN เพื่อดูข้อมูลแบบเรียลไทม์',
        pinHint: 'กรอกครบแล้วเข้าใช้งานได้ทันที',
        pinLocked: 'ล็อกอยู่ {seconds} วินาที',
        pinWrong: 'PIN ไม่ถูกต้อง',
        pinWrongMaxLock: 'PIN ผิดเกินกำหนด ล็อกชั่วคราว 90 วินาที',
        pinLockedShort: 'PIN ถูกล็อกชั่วคราว',
        clear: 'ล้าง',
        backspace: 'ลบ',
        operationsMonitor: 'Operations Monitor',
        realtimeV4: 'Real-time V.4',
        dashboardSubtitle: 'ติดตามการนับเที่ยวรถและรอบร่อนทรายจากแอปมือถือแบบเรียลไทม์',
        viewing: 'กำลังดู',
        today: 'วันนี้',
        shareLink: 'แชร์ลิงก์',
        selectDate: 'เลือกวันที่',
        backToToday: 'กลับวันนี้',
        showOnly: 'แสดงเฉพาะ',
        expense: 'รายจ่าย',
        income: 'รายรับ',
        netProfit: 'กำไรสุทธิ',
        tripUnit: 'เที่ยว',
        roundUnit: 'รอบ',
        live: 'Live',
        countRecord: 'Count & Record',
        countAndRecord: 'บันทึกและนับจำนวน',
        waitingMobile: 'รอข้อมูลจากแอปมือถือ',
        tripCountTitle: 'จำนวนเที่ยวรถ',
        sandTitle: 'การร่อนทราย',
        tripSubtitle: '{vehicles} คัน · รวม {total} เที่ยว',
        sandSubtitle: '{rounds} รอบวันนี้',
        sandSubtitleEmpty: 'ยังไม่มีการนับรอบ',
        noTripsTitle: 'ยังไม่มีเที่ยวที่บันทึก',
        noTripsSubtitle: 'เมื่อกดนับเที่ยวในแอป ข้อมูลจะปรากฏที่นี่ทันที',
        noSandTitle: 'ยังไม่มีรอบที่บันทึก',
        noSandSubtitle: 'กดนับรอบร่อนทรายในแอปเพื่อติดตามแบบเรียลไทม์',
        latestLog: 'บันทึกล่าสุด',
        noTimestamp: 'ยังไม่มี timestamp',
        morning: 'เช้า',
        afternoon: 'บ่าย',
        ot: 'OT',
        vehicleNo: 'คันที่ {n}',
        brokenVehicle: 'รถเสีย',
        roundLabel: 'รอบ',
        recentLaps: 'รอบล่าสุด',
        activityStream: 'Activity stream',
        activityFromMobile: 'อัปเดตล่าสุดจากมือถือ',
        statusLive: 'Live',
        statusPolling: 'Polling',
        statusConnecting: 'Connecting',
        realtimeConnected: 'เชื่อมต่อ Supabase Realtime',
        pollFallback: 'สำรองดึงข้อมูลทุก 12 วินาที',
        connectingChannel: 'กำลังเชื่อมต่อช่องสัญญาณ…',
        syncRealtime: 'Realtime',
        syncPoll: 'Auto-sync',
        syncLocal: 'Updated',
        mobileOnline: 'มือถือออนไลน์ {count} เครื่อง',
        mobileOffline: 'มือถือออฟไลน์',
        mobileRealtime: 'เชื่อมต่อแอปมือถือแบบ Real-time',
        mobileWaiting: 'รอแอปมือถือเปิดอยู่',
        mobileConnecting: 'กำลังเชื่อมต่อ…',
        paceAnalytics: 'วิเคราะห์จังหวะ',
        lunchBreakNote: 'หักพักเที่ยง 12:00–13:00 น.',
        lunchBreak: 'พักเที่ยง',
        avgPace: 'จังหวะเฉลี่ย',
        paceVsYesterday: 'Pace vs เมื่อวาน',
        paceVsPriorDay: 'Pace vs {label}',
        totalRounds: 'ยอดรวม',
        workTime: 'เวลาทำงาน',
        workTimeFleet: 'เวลาทำงานรถ',
        workSpan: 'ช่วงจังหวะ',
        fastest: 'เร็วสุด',
        slowest: 'ช้าสุด',
        targetHours: 'เป้า {hours} ชม.',
        lastPace: 'ล่าสุด {sec} วิน.',
        morningAfternoonSplit: 'สัดส่วนเช้า / บ่าย',
        noMorningAfternoon: 'ยังไม่มีข้อมูลเช้า/บ่าย',
        peakHour: 'ช่วงพีค (รายชั่วโมง)',
        noPeakHour: 'ยังไม่มีช่วงพีค',
        peakHourLabel: 'ช่วงคึกคักสุด',
        peakHourHint: 'ชั่วโมงที่มีการนับมากที่สุด',
        heatmapHourly: 'Heatmap รายชั่วโมง',
        noHourlyData: 'ยังไม่มีข้อมูลรายชั่วโมง',
        cumulativeByTime: 'ยอดสะสม{unit}ตามเวลา',
        countPerHour: 'จำนวน{unit}ต่อชั่วโมง',
        speedPerHour: 'ความเร็ว{unit}ต่อชั่วโมง',
        vehicleComparison: 'เปรียบเทียบคัน',
        noVehicleData: 'ยังไม่มีข้อมูลรถ',
        perVehicleSummary: 'สรุปรายคัน',
        sandWorkHourly: 'เวลาทำงานรายชั่วโมง (ชม.)',
        sandSpeedHourly: 'ความเร็วร่อนต่อชั่วโมง (รอบ/ชม.)',
        sandSpeedMinute: 'Timeline ความเร็วร่อนต่อนาที',
        fleetWorkHourly: 'เวลาทำงานรถรวมรายชั่วโมง (ชม.)',
        sandPeriodEfficiency: 'ประสิทธิภาพแยกช่วง',
        sandTargetEta: 'คาดการณ์ถึงเป้า',
        sandPaceConsistency: 'ความสม่ำเสมอของจังหวะ',
        roundsPerHourShort: 'รอบ/ชม.',
        remainingRounds: 'เหลือ {n} รอบ',
        etaReachTarget: 'คาดถึงเป้า ~{time}',
        targetReached: 'ถึงเป้าแล้ว',
        paceSteady: 'จังหวะนิ่ง',
        paceUneven: 'จังหวะสะดุด',
        paceModerate: 'จังหวะปานกลาง',
        needMoreLaps: 'ต้องมีอย่างน้อย 3 ช่วงรอบ',
        needTwoRoundsPeriod: 'ต้องมีอย่างน้อย 2 รอบในช่วง',
        noWorkTimeData: 'ยังไม่มีข้อมูลเวลาทำงาน',
        noSpeedData: 'ยังไม่มีข้อมูลความเร็ว',
        needTwoRounds: 'ต้องมีอย่างน้อย 2 รอบ',
        minuteTimelineHint: 'รอบ/นาที · เลื่อนดูรายละเอียด',
        chartTouchHint: 'แตะ/ชี้เพื่อดูรายละเอียด',
        chartCumulativeShort: 'สะสม {value} {unit}',
        chartMaxSpeed: 'สูงสุด {value} รอบ/นาที',
        roundsPerMinute: 'รอบ/นาที',
        vsYesterdayCumulative: 'เปรียบเทียบกับเมื่อวาน (สะสม)',
        vsPriorDayCumulative: 'เปรียบเทียบกับ {label} (สะสม)',
        moreThanYesterday: 'มากกว่าเมื่อวาน {pct}%',
        lessThanYesterday: 'น้อยกว่าเมื่อวาน {pct}%',
        moreThanPriorDay: 'มากกว่า{label} {pct}%',
        lessThanPriorDay: 'น้อยกว่า{label} {pct}%',
        paceSamePriorDay: 'เท่า{label}',
        queueCount: 'จำนวนคิว',
        queueUnit: 'คิว',
        queuePerTripNote: '1 เที่ยว = 4 คิว',
        paceDetailTitle: 'รายละเอียดจังหวะ',
        tapForDetail: 'แตะเพื่อดูรายละเอียด',
        perVehiclePace: 'จังหวะรายคัน',
        peakHourRange: '{start} – {end}',
        sandKpiTitle: 'วิเคราะห์ร่อนทราย',
        speedPerHourShort: '{v} รอบ/ชม.',
        speedPerMinuteShort: '{v} รอบ/นาที',
        targetLabel: 'เป้าหมาย',
        targetProgress: '{current}/{target}',
        tripTotalTitle: 'รวมเที่ยววันนี้',
        perVehicleTitle: 'ประสิทธิภาพต่อคัน',
        perVehicleAvg: 'เฉลี่ย {v} เที่ยว/คัน',
        vehicleCountLabel: '{n} คัน',
        moreEfficientYesterday: 'คุ้มกว่าเมื่อวาน {pct}%',
        lessEfficientYesterday: 'น้อยกว่าเมื่อวาน {pct}%',
        moreEfficientPriorDay: 'คุ้มกว่า{label} {pct}%',
        lessEfficientPriorDay: 'น้อยกว่า{label} {pct}%',
        perHourUnit: '{unit}/ชม.',
        todayLabel: 'วันนี้',
        yesterdayLabel: 'เมื่อวาน',
        paceSameYesterday: 'เท่าเมื่อวาน',
        paceFasterYesterday: 'เร็วกว่าเมื่อวาน {pct}%',
        paceSlowerYesterday: 'ช้ากว่าเมื่อวาน {pct}%',
        noYesterdayData: 'ไม่มีข้อมูลเมื่อวาน',
        noPriorDayData: 'ไม่มีข้อมูลเปรียบเทียบ',
        avgPaceLabel: 'จังหวะเฉลี่ย',
        latestLabel: 'ล่าสุด',
        vehiclesTripsStatus: '{vehicles} คัน · {trips} เที่ยว',
        sandStatus: 'ร่อน {rounds} รอบ',
        sandStatusPeriod: ' (เช้า {morning} · บ่าย {afternoon})',
        tripActivityNew: '{vehicle} • เที่ยวที่ {rounds} • {lap}',
        tripActivityCount: '{vehicle} • {rounds} เที่ยว',
        tripActivityAdded: '{vehicle} • เพิ่มเป็น {rounds} เที่ยว',
        sandActivityLap: 'รอบที่ {rounds} • {lap}',
        sandActivityCount: 'ร่อนทราย • {rounds} รอบ',
        workStart: 'เริ่ม {time}',
        workStartEnd: 'เริ่ม {start} · เลิก {end}',
        secUnit: 'วิน.',
        minUnit: 'นาที',
        hourUnit: 'ชม.',
        hourShort: '0 ชม.',
        minutesShort: '{mins} นาที',
        hoursShort: '{hours} ชม.',
        macroUsageTitle: 'รายงานการใช้รถแม็คโคร',
        macroUsageEmpty: 'ยังไม่มีการใช้แม็คโครวันนี้',
        macroVehicleCount: 'ใช้ {n} คัน',
        macroFuelTotal: 'รวมน้ำมัน',
        macroNoWorkDetail: 'ยังไม่ระบุงาน',
        fullDay: 'เต็มวัน',
        halfDay: 'ครึ่งวัน',
        attendanceTitle: 'พนักงานมาทำงานวันนี้',
        attendanceSubtitle: 'มาทำงาน {n} คน',
        attendanceLeave: 'ลา {n}',
        attendanceAbsent: 'ขาด {n}',
        attendanceEmpty: 'ยังไม่มีการบันทึกมาทำงาน',
        personUnit: 'คน',
        vehicleUnit: 'คัน',
        litersUnit: 'ลิตร',
    },
    zh: {
        langShort: '中文',
        langToggle: 'TH',
        themeLight: '浅色模式',
        themeDark: '深色模式',
        loading: '加载中...',
        cannotOpenDashboard: '无法打开仪表板',
        shareNotFound: '未找到分享设置',
        shareDisabled: '分享链接已关闭',
        invalidLink: '链接无效或已过期',
        pinNotSet: '尚未设置 PIN 码',
        realtimeBanner: '实时查看模式 — 自动更新',
        pinTitle: '实时仪表板',
        pinSubtitle: '输入 PIN 码查看实时数据',
        pinHint: '输入正确后自动进入',
        pinLocked: '已锁定 {seconds} 秒',
        pinWrong: 'PIN 码不正确',
        pinWrongMaxLock: 'PIN 错误次数过多，锁定 90 秒',
        pinLockedShort: 'PIN 已临时锁定',
        clear: '清除',
        backspace: '删除',
        operationsMonitor: '运营监控',
        realtimeV4: '实时 V.4',
        dashboardSubtitle: '实时跟踪手机应用的车辆趟次与洗沙轮次',
        viewing: '正在查看',
        today: '今天',
        shareLink: '分享链接',
        selectDate: '选择日期',
        backToToday: '返回今天',
        showOnly: '仅显示',
        expense: '支出',
        income: '收入',
        netProfit: '净利润',
        tripUnit: '趟',
        roundUnit: '轮',
        live: '实时',
        countRecord: '计数记录',
        countAndRecord: '记录与计数',
        waitingMobile: '等待手机应用数据',
        tripCountTitle: '车辆趟次',
        sandTitle: '洗沙轮次',
        tripSubtitle: '{vehicles} 辆 · 共 {total} 趟',
        sandSubtitle: '今日 {rounds} 轮',
        sandSubtitleEmpty: '暂无轮次记录',
        noTripsTitle: '暂无趟次记录',
        noTripsSubtitle: '在手机应用计数后，数据将立即显示',
        noSandTitle: '暂无轮次记录',
        noSandSubtitle: '在手机应用计数洗沙轮次以实时跟踪',
        latestLog: '最新记录',
        noTimestamp: '暂无时间戳',
        morning: '上午',
        afternoon: '下午',
        ot: '加班',
        vehicleNo: '第 {n} 辆',
        brokenVehicle: '车辆故障',
        roundLabel: '轮',
        recentLaps: '最近轮次',
        activityStream: '活动流',
        activityFromMobile: '手机最新更新',
        statusLive: '实时',
        statusPolling: '轮询',
        statusConnecting: '连接中',
        realtimeConnected: '已连接 Supabase 实时',
        pollFallback: '每 12 秒自动同步',
        connectingChannel: '正在连接频道…',
        syncRealtime: '实时',
        syncPoll: '自动同步',
        syncLocal: '已更新',
        mobileOnline: '手机在线 {count} 台',
        mobileOffline: '手机离线',
        mobileRealtime: '手机应用实时连接',
        mobileWaiting: '等待手机应用上线',
        mobileConnecting: '连接中…',
        paceAnalytics: '节奏分析',
        lunchBreakNote: '已扣除午休 12:00–13:00',
        lunchBreak: '午休',
        avgPace: '平均节奏',
        paceVsYesterday: '对比昨日节奏',
        paceVsPriorDay: '对比 {label} 节奏',
        totalRounds: '总计',
        workTime: '工作时间',
        workTimeFleet: '车辆工作时间',
        workSpan: '节奏区间',
        fastest: '最快',
        slowest: '最慢',
        targetHours: '目标 {hours} 小时',
        lastPace: '最近 {sec} 秒',
        morningAfternoonSplit: '上午 / 下午占比',
        noMorningAfternoon: '暂无上午/下午数据',
        peakHour: '高峰时段（按小时）',
        noPeakHour: '暂无高峰时段',
        peakHourLabel: '最繁忙时段',
        peakHourHint: '计数最多的小时',
        heatmapHourly: '每小时热力图',
        noHourlyData: '暂无每小时数据',
        cumulativeByTime: '累计{unit}趋势',
        countPerHour: '每小时{unit}数',
        speedPerHour: '每小时{unit}速度',
        vehicleComparison: '车辆对比',
        noVehicleData: '暂无车辆数据',
        perVehicleSummary: '分车汇总',
        sandWorkHourly: '每小时工作时间（小时）',
        sandSpeedHourly: '每小时洗沙速度（轮/时）',
        sandSpeedMinute: '每分钟速度时间线',
        fleetWorkHourly: '车队每小时工作时间（小时）',
        sandPeriodEfficiency: '分时段效率',
        sandTargetEta: '目标到达预估',
        sandPaceConsistency: '节奏稳定性',
        roundsPerHourShort: '轮/时',
        remainingRounds: '还剩 {n} 轮',
        etaReachTarget: '预计 ~{time} 达标',
        targetReached: '已达目标',
        paceSteady: '节奏稳定',
        paceUneven: '节奏不稳',
        paceModerate: '节奏一般',
        needMoreLaps: '至少需要 3 个间隔',
        needTwoRoundsPeriod: '该时段至少需要 2 轮',
        noWorkTimeData: '暂无工作时间数据',
        noSpeedData: '暂无速度数据',
        needTwoRounds: '至少需要 2 轮数据',
        minuteTimelineHint: '轮/分钟 · 滑动查看详情',
        chartTouchHint: '点击/悬停查看详情',
        chartCumulativeShort: '累计 {value} {unit}',
        chartMaxSpeed: '最高 {value} 轮/分钟',
        roundsPerMinute: '轮/分钟',
        vsYesterdayCumulative: '与昨天对比（累计）',
        vsPriorDayCumulative: '与 {label} 对比（累计）',
        moreThanYesterday: '比昨天多 {pct}%',
        lessThanYesterday: '比昨天少 {pct}%',
        moreThanPriorDay: '比{label}多 {pct}%',
        lessThanPriorDay: '比{label}少 {pct}%',
        paceSamePriorDay: '与{label}相同',
        queueCount: '斗数',
        queueUnit: '斗',
        queuePerTripNote: '1 趟 = 4 斗',
        paceDetailTitle: '节奏详情',
        tapForDetail: '点击查看详情',
        perVehiclePace: '分车节奏',
        peakHourRange: '{start} – {end}',
        sandKpiTitle: '洗沙分析',
        speedPerHourShort: '{v} 轮/时',
        speedPerMinuteShort: '{v} 轮/分钟',
        targetLabel: '目标',
        targetProgress: '{current}/{target}',
        tripTotalTitle: '今日总趟数',
        perVehicleTitle: '每车效率',
        perVehicleAvg: '平均 {v} 趟/车',
        vehicleCountLabel: '{n} 车',
        moreEfficientYesterday: '比昨天高效 {pct}%',
        lessEfficientYesterday: '比昨天低 {pct}%',
        moreEfficientPriorDay: '比{label}高效 {pct}%',
        lessEfficientPriorDay: '比{label}低 {pct}%',
        perHourUnit: '{unit}/时',
        todayLabel: '今天',
        yesterdayLabel: '昨天',
        paceSameYesterday: '与昨天相同',
        paceFasterYesterday: '比昨天快 {pct}%',
        paceSlowerYesterday: '比昨天慢 {pct}%',
        noYesterdayData: '无昨天数据',
        noPriorDayData: '无对比数据',
        avgPaceLabel: '平均节奏',
        latestLabel: '最近',
        vehiclesTripsStatus: '{vehicles} 辆 · {trips} 趟',
        sandStatus: '洗沙 {rounds} 轮',
        sandStatusPeriod: ' (上午 {morning} · 下午 {afternoon})',
        tripActivityNew: '{vehicle} • 第 {rounds} 趟 • {lap}',
        tripActivityCount: '{vehicle} • {rounds} 趟',
        tripActivityAdded: '{vehicle} • 增至 {rounds} 趟',
        sandActivityLap: '第 {rounds} 轮 • {lap}',
        sandActivityCount: '洗沙 • {rounds} 轮',
        workStart: '开始 {time}',
        workStartEnd: '开始 {start} · 结束 {end}',
        secUnit: '秒',
        minUnit: '分钟',
        hourUnit: '小时',
        hourShort: '0 小时',
        minutesShort: '{mins} 分钟',
        hoursShort: '{hours} 小时',
        macroUsageTitle: '挖掘机使用报告',
        macroUsageEmpty: '今日暂无挖掘机使用记录',
        macroVehicleCount: '使用 {n} 辆',
        macroFuelTotal: '总用油量',
        macroNoWorkDetail: '暂无工作说明',
        fullDay: '全天',
        halfDay: '半天',
        attendanceTitle: '今日出勤员工',
        attendanceSubtitle: '出勤 {n} 人',
        attendanceLeave: '请假 {n}',
        attendanceAbsent: '缺勤 {n}',
        attendanceEmpty: '暂无出勤记录',
        personUnit: '人',
        vehicleUnit: '辆',
        litersUnit: '升',
    },
} as const;

export type ShareMessageKey = keyof typeof messages.th;

export const readSavedShareLocale = (): ShareLocale => {
    if (typeof window === 'undefined') return 'th';
    const raw = window.localStorage.getItem(LOCALE_KEY);
    return raw === 'zh' ? 'zh' : 'th';
};

export const saveShareLocale = (locale: ShareLocale) => {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(LOCALE_KEY, locale);
};

export const readSavedShareTheme = (): ShareTheme | null => {
    if (typeof window === 'undefined') return null;
    const raw = window.localStorage.getItem(THEME_KEY);
    return raw === 'light' || raw === 'dark' ? raw : null;
};

export const saveShareTheme = (theme: ShareTheme) => {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(THEME_KEY, theme);
};

export const resolveInitialShareTheme = (): ShareTheme => {
    const saved = readSavedShareTheme();
    if (saved) return saved;
    if (typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches) {
        return 'dark';
    }
    return 'light';
};

export const applyShareThemeToDocument = (theme: ShareTheme) => {
    if (typeof document === 'undefined') return;
    document.documentElement.classList.toggle('dark', theme === 'dark');
};

export const formatShareDate = (ymd: string, locale: ShareLocale) =>
    new Date(ymd + 'T12:00:00+07:00').toLocaleDateString(locale === 'zh' ? 'zh-CN' : 'th-TH', {
        timeZone: 'Asia/Bangkok',
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        year: '2-digit',
    });

export const formatShareTime = (ts: number, locale: ShareLocale) =>
    new Date(ts).toLocaleTimeString(locale === 'zh' ? 'zh-CN' : 'th-TH', {
        timeZone: 'Asia/Bangkok',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });

export const formatShareNumber = (value: number, locale: ShareLocale) =>
    value.toLocaleString(locale === 'zh' ? 'zh-CN' : 'th-TH');

const defaultContext = {
    locale: 'th' as ShareLocale,
    theme: 'light' as ShareTheme,
    t: (key: ShareMessageKey, params?: Record<string, string | number>) => {
        let text: string = messages.th[key];
        if (params) {
            for (const [k, v] of Object.entries(params)) {
                text = text.replace(`{${k}}`, String(v));
            }
        }
        return text;
    },
    setLocale: (_locale: ShareLocale) => {},
    toggleLocale: () => {},
    setTheme: (_theme: ShareTheme) => {},
    toggleTheme: () => {},
    formatDate: (ymd: string) => formatShareDate(ymd, 'th'),
    formatTime: (ts: number) => formatShareTime(ts, 'th'),
    formatNumber: (value: number) => formatShareNumber(value, 'th'),
    roundLabelTrip: () => messages.th.tripUnit,
    roundLabelSand: () => messages.th.roundUnit,
};

const ShareLocaleContext = createContext(defaultContext);

function interpolate(locale: ShareLocale, key: ShareMessageKey, params?: Record<string, string | number>) {
    let text: string = messages[locale][key] ?? messages.th[key];
    if (params) {
        for (const [k, v] of Object.entries(params)) {
            text = text.replace(`{${k}}`, String(v));
        }
    }
    return text;
}

export function SharePreferencesProvider({ children }: { children: ReactNode }) {
    const [locale, setLocaleState] = useState<ShareLocale>(() => readSavedShareLocale());
    const [theme, setThemeState] = useState<ShareTheme>(() => resolveInitialShareTheme());

    useEffect(() => {
        applyShareThemeToDocument(theme);
    }, [theme]);

    const setLocale = useCallback((next: ShareLocale) => {
        setLocaleState(next);
        saveShareLocale(next);
    }, []);

    const toggleLocale = useCallback(() => {
        setLocale(locale === 'th' ? 'zh' : 'th');
    }, [locale, setLocale]);

    const setTheme = useCallback((next: ShareTheme) => {
        setThemeState(next);
        saveShareTheme(next);
    }, []);

    const toggleTheme = useCallback(() => {
        setTheme(theme === 'dark' ? 'light' : 'dark');
    }, [theme, setTheme]);

    const value = useMemo(
        () => ({
            locale,
            theme,
            t: (key: ShareMessageKey, params?: Record<string, string | number>) => interpolate(locale, key, params),
            setLocale,
            toggleLocale,
            setTheme,
            toggleTheme,
            formatDate: (ymd: string) => formatShareDate(ymd, locale),
            formatTime: (ts: number) => formatShareTime(ts, locale),
            formatNumber: (value: number) => formatShareNumber(value, locale),
            roundLabelTrip: () => (locale === 'zh' ? messages.zh.tripUnit : messages.th.tripUnit),
            roundLabelSand: () => (locale === 'zh' ? messages.zh.roundUnit : messages.th.roundUnit),
        }),
        [locale, theme, setLocale, toggleLocale, setTheme, toggleTheme],
    );

    return <ShareLocaleContext.Provider value={value}>{children}</ShareLocaleContext.Provider>;
}

export function useShareLocale() {
    return useContext(ShareLocaleContext);
}

export function SharePreferenceControls({ className = '' }: { className?: string }) {
    const { locale, theme, toggleLocale, toggleTheme, t } = useShareLocale();

    return (
        <div className={`flex items-center gap-1.5 ${className}`}>
            <button
                type="button"
                onClick={toggleTheme}
                className="inline-flex h-9 min-w-[2.25rem] items-center justify-center rounded-xl border border-slate-200/80 bg-white/90 px-2.5 text-xs font-bold text-slate-700 shadow-sm transition hover:bg-slate-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                aria-label={theme === 'dark' ? t('themeLight') : t('themeDark')}
                title={theme === 'dark' ? t('themeLight') : t('themeDark')}
            >
                {theme === 'dark' ? '☀' : '☾'}
            </button>
            <button
                type="button"
                onClick={toggleLocale}
                className="inline-flex h-9 min-w-[2.75rem] items-center justify-center rounded-xl border border-slate-200/80 bg-white/90 px-2.5 text-xs font-bold text-slate-700 shadow-sm transition hover:bg-slate-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            >
                {locale === 'th' ? t('langToggle') : t('langShort')}
            </button>
        </div>
    );
}
