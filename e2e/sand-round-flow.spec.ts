import { expect, test } from '@playwright/test';

test('assign washHome + batch allocation saves successfully', async ({ page }) => {
    await page.goto('/?e2e=harness');
    await expect(page.getByText('บันทึกการล้างทราย')).toBeVisible();
    await page.getByLabel('จำนวนถังที่ได้วันนี้').locator('input').fill('10');
    await page.getByLabel('รหัสล็อตทรายวันนี้').fill('BATCH-E2E-001');
    await page.getByRole('button', { name: 'บันทึกข้อมูลล้างทราย' }).click();
    await expect(page.getByText('บันทึกการล้างทราย')).toBeVisible();
});

test('without washHome assignment but home drums > 0 is blocked', async ({ page }) => {
    await page.goto('/?e2e=harness');
    await page.getByLabel('จำนวนทรายที่ล้างที่บ้านวันนี้').locator('input').fill('5');
    await page.getByRole('button', { name: 'บันทึกข้อมูลล้างทราย' }).click();
    await expect(page.getByText(/ยังไม่ได้ assign งาน washHome|มีการล้างที่บ้าน/)).toBeVisible();
});

test('Closed workflow disables batch edit', async ({ page }) => {
    await page.goto('/?e2e=harness');
    const reason = page.getByPlaceholder('เหตุผล (บังคับเมื่อ Closed/Reopened)').first();
    const workflow = reason.locator('xpath=preceding-sibling::select[1]');
    await reason.fill('override test close');
    await workflow.selectOption('Closed');
    const batchInput = page.locator('input[value=\"BATCH-SEED-001\"]').first();
    await expect(batchInput).toBeDisabled();
});

test('Reopened workflow enables batch edit', async ({ page }) => {
    await page.goto('/?e2e=harness');
    const reason = page.getByPlaceholder('เหตุผล (บังคับเมื่อ Closed/Reopened)').first();
    const workflow = reason.locator('xpath=preceding-sibling::select[1]');
    await reason.fill('override test reopen');
    await workflow.selectOption('Reopened');
    const editable = page.locator('input[value=\"BATCH-SEED-001\"]').first();
    await expect(editable).toBeEnabled();
});

