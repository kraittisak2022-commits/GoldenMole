export type AppLocale = 'th' | 'en';

const APP_LOCALE_KEY = 'cm_app_locale_v1';

const messages = {
    th: {
        languageShort: 'TH',
        toggleLanguage: 'สลับเป็น English',
        loadingPreparing: 'กำลังเตรียมระบบ...',
        loadingSeed: 'กำลังเตรียมข้อมูลเริ่มต้น...',
        loadingRemote: 'กำลังโหลดข้อมูลจากฐานข้อมูล...',
        loadingProcess: 'กำลังประมวลผลข้อมูล...',
        loadingOk: 'โหลดข้อมูลสำเร็จ',
        loadingFallback: 'เชื่อมต่อฐานข้อมูลไม่สำเร็จ กำลังใช้ข้อมูลสำรอง...',
        loadingFallbackOk: 'โหลดข้อมูลสำรองสำเร็จ',
        syncing: 'กำลังซิงก์...',
        menu: 'เมนู',
    },
    en: {
        languageShort: 'EN',
        toggleLanguage: 'Switch to Thai',
        loadingPreparing: 'Preparing system...',
        loadingSeed: 'Preparing initial data...',
        loadingRemote: 'Loading data from server...',
        loadingProcess: 'Processing data...',
        loadingOk: 'Data loaded successfully',
        loadingFallback: 'Server unavailable, using fallback data...',
        loadingFallbackOk: 'Fallback data loaded',
        syncing: 'Syncing...',
        menu: 'Menu',
    },
} as const;

export const readSavedLocale = (): AppLocale => {
    if (typeof window === 'undefined') return 'th';
    const raw = window.localStorage.getItem(APP_LOCALE_KEY);
    return raw === 'en' ? 'en' : 'th';
};

export const saveLocale = (locale: AppLocale) => {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(APP_LOCALE_KEY, locale);
};

export const t = (locale: AppLocale, key: keyof typeof messages.th): string => {
    return messages[locale][key] ?? messages.th[key];
};
