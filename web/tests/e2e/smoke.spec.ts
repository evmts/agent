import { expect, test } from "@playwright/test";

test("smoke renders app shell", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#root")).toBeVisible();
  await expect(page.getByText("Smithers v2")).toBeVisible();
  await expect(page.getByPlaceholder("Message Smithers...")).toBeVisible();
});
