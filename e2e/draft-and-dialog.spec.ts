import { expect, test } from '@playwright/test';

test('shows autosave status in harness', async ({ page }) => {
    await page.goto('/?e2e=harness');
    await expect(page.getByRole('heading', { name: 'E2E Harness' })).toBeVisible();
    await expect(page.getByRole('status')).toContainText(/กำลังบันทึกแบบร่าง|บันทึกล่าสุด/);
});

test('conflict draft shows detailed warning and section toggles', async ({ page }) => {
    await page.goto('/?e2e=harness');
    await page.getByRole('button', { name: 'Seed Conflict Draft' }).click();
    await page.reload();
    await expect(page.getByText('พบแบบร่างที่ยังไม่เสร็จ')).toBeVisible();
    await expect(page.getByText(/เดิม \d+ รายการ, ปัจจุบัน \d+ รายการ/)).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'ค่าแรง' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'น้ำมัน' })).toBeVisible();
});

test('clear all drafts removes banner after reload', async ({ page }) => {
    await page.goto('/?e2e=harness');
    await page.getByRole('button', { name: 'Seed Matching Draft' }).click();
    await page.reload();
    await expect(page.getByText('พบแบบร่างที่ยังไม่เสร็จ')).toBeVisible();

    await page.getByRole('button', { name: 'ล้างแบบร่างทั้งหมด' }).click();
    await page.getByRole('button', { name: 'ตกลง' }).click();
    await page.reload();

    await expect(page.getByText('พบแบบร่างที่ยังไม่เสร็จ')).toHaveCount(0);
});
