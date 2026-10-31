import { expect, test } from "@playwright/test";
import { rand, signUp, uploadCsv, waitForImportStatus } from "./helpers";

test("uploads a small CSV and reaches completed", async ({ page }) => {
  await signUp(page, `${rand("small")}@example.com`, "secret123", "Small");
  await uploadCsv(page, "small.csv");

  const status = await waitForImportStatus(
    page,
    ["completed", "completed_with_errors"],
    45_000,
  );
  expect(["completed", "completed_with_errors"]).toContain(status);

  // The "processed" metric tile should show 5 rows.
  await expect(page.locator("dd").nth(1)).toHaveText("5");
});

test("invalid rows land in completed_with_errors and surface in the chunk table", async ({
  page,
}) => {
  await signUp(page, `${rand("bad")}@example.com`, "secret123", "Bad");
  await uploadCsv(page, "with_errors.csv");

  const status = await waitForImportStatus(
    page,
    ["completed_with_errors", "partially_failed", "failed"],
    45_000,
  );
  expect(["completed_with_errors", "partially_failed"]).toContain(status);

  // At least one row-level error should be visible.
  await expect(
    page.getByText(/invalid format|must be|not a decimal/).first(),
  ).toBeVisible();
});
