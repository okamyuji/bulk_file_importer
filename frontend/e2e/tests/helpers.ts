import { expect, type Page } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
export const FIXTURES = path.resolve(here, "..", "fixtures");

export function rand(prefix = "u"): string {
  return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

export async function signUp(page: Page, email: string, password: string, name: string): Promise<void> {
  await page.goto("/login");
  await expect(page.getByRole("heading", { name: /サインイン/ })).toBeVisible();
  await page.getByTestId("toggle-signup").click();
  await expect(page.getByRole("heading", { name: /アカウント作成/ })).toBeVisible();
  await page.getByLabel(/お名前/).fill(name);
  await page.getByLabel(/メールアドレス/).fill(email);
  await page.getByLabel(/パスワード/).fill(password);
  await page.getByTestId("submit").click();
  await expect(page).toHaveURL(/\/imports(\?|$)/, { timeout: 15_000 });
}

export async function signIn(page: Page, email: string, password: string): Promise<void> {
  await page.goto("/login");
  await expect(page.getByRole("heading", { name: /サインイン/ })).toBeVisible();
  await page.getByLabel(/メールアドレス/).fill(email);
  await page.getByLabel(/パスワード/).fill(password);
  await page.getByTestId("submit").click();
  await expect(page).toHaveURL(/\/imports(\?|$)/, { timeout: 15_000 });
}

export async function uploadCsv(page: Page, fixture: string, targetKind = "sales_record"): Promise<void> {
  await page.goto("/imports/new");
  if (targetKind === "ledger_entry") {
    await page.getByRole("radio", { name: "仕訳" }).click();
  }
  await page.locator('input[type="file"]').setInputFiles(path.join(FIXTURES, fixture));
  await page.getByRole("button", { name: /インポート開始/ }).click();
  await page.waitForURL(/\/imports\/\d+/);
}

export async function waitForImportStatus(
  page: Page,
  statuses: string[] | string,
  timeout = 30_000,
): Promise<string> {
  const list = Array.isArray(statuses) ? statuses : [statuses];
  const deadline = Date.now() + timeout;
  let last = "";
  while (Date.now() < deadline) {
    const badge = await page
      .locator("span")
      .filter({
        hasText: /^(pending|splitting|processing|completed|completed_with_errors|partially_failed|failed)$/,
      })
      .first()
      .textContent();
    last = badge?.trim() ?? "";
    if (list.includes(last)) return last;
    await page.waitForTimeout(500);
  }
  throw new Error(`Timed out waiting for status ${list.join("|")}, last was "${last}"`);
}
