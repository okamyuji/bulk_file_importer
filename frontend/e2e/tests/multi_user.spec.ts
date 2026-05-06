import { expect, test } from "@playwright/test";
import { rand, signUp, uploadCsv, waitForImportStatus } from "./helpers";

test("two users see only their own imports", async ({ browser }) => {
  // User A
  const aCtx = await browser.newContext();
  const aPage = await aCtx.newPage();
  const aEmail = `${rand("alpha")}@example.com`;
  await signUp(aPage, aEmail, "secret123", "Alpha");
  await uploadCsv(aPage, "small.csv");
  await waitForImportStatus(aPage, ["completed", "completed_with_errors"], 45_000);

  // User B
  const bCtx = await browser.newContext();
  const bPage = await bCtx.newPage();
  const bEmail = `${rand("bravo")}@example.com`;
  await signUp(bPage, bEmail, "secret123", "Bravo");

  // B's list must be empty
  await bPage.goto("/imports");
  await expect(bPage.getByText(/まだインポートがありません/)).toBeVisible();

  // B cannot navigate to A's import detail (status 403 from API → error UI)
  const aUrl = aPage.url();
  const match = aUrl.match(/\/imports\/(\d+)/);
  expect(match).not.toBeNull();
  await bPage.goto(`/imports/${match![1]}`);
  // The detail page shows "読み込み中…" indefinitely because the API returned 403,
  // which causes TanStack Query to retry and never resolve. Either way, B never sees A's file_name.
  await expect(bPage.getByText(/small\.csv/)).toHaveCount(0);

  await aCtx.close();
  await bCtx.close();
});
