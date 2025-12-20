import { test, expect, describe } from "bun:test";
import {
  formatRelativeTime,
  formatAbsoluteTime,
  formatFullDateTime,
  formatShortRelativeTime,
} from "../time";

describe("formatRelativeTime", () => {
  test("returns 'in the future' for future dates", () => {
    const futureDate = new Date(Date.now() + 10000);
    expect(formatRelativeTime(futureDate)).toBe("in the future");
  });

  test("returns 'just now' for dates less than 60 seconds ago", () => {
    const now = new Date(Date.now() - 30000); // 30 seconds ago
    expect(formatRelativeTime(now)).toBe("just now");
  });

  test("returns minutes for dates less than 60 minutes ago", () => {
    const oneMinuteAgo = new Date(Date.now() - 60000);
    expect(formatRelativeTime(oneMinuteAgo)).toBe("1 minute ago");

    const fiveMinutesAgo = new Date(Date.now() - 300000);
    expect(formatRelativeTime(fiveMinutesAgo)).toBe("5 minutes ago");

    const thirtyMinutesAgo = new Date(Date.now() - 1800000);
    expect(formatRelativeTime(thirtyMinutesAgo)).toBe("30 minutes ago");
  });

  test("returns hours for dates less than 24 hours ago", () => {
    const oneHourAgo = new Date(Date.now() - 3600000);
    expect(formatRelativeTime(oneHourAgo)).toBe("1 hour ago");

    const fiveHoursAgo = new Date(Date.now() - 18000000);
    expect(formatRelativeTime(fiveHoursAgo)).toBe("5 hours ago");

    const twentyHoursAgo = new Date(Date.now() - 72000000);
    expect(formatRelativeTime(twentyHoursAgo)).toBe("20 hours ago");
  });

  test("returns days for dates less than 30 days ago", () => {
    const oneDayAgo = new Date(Date.now() - 86400000);
    expect(formatRelativeTime(oneDayAgo)).toBe("1 day ago");

    const fiveDaysAgo = new Date(Date.now() - 432000000);
    expect(formatRelativeTime(fiveDaysAgo)).toBe("5 days ago");

    const twentyDaysAgo = new Date(Date.now() - 1728000000);
    expect(formatRelativeTime(twentyDaysAgo)).toBe("20 days ago");
  });

  test("returns months for dates less than 12 months ago", () => {
    const oneMonthAgo = new Date(Date.now() - 2592000000); // ~30 days
    expect(formatRelativeTime(oneMonthAgo)).toBe("1 month ago");

    const threeMonthsAgo = new Date(Date.now() - 7776000000); // ~90 days
    expect(formatRelativeTime(threeMonthsAgo)).toBe("3 months ago");

    const elevenMonthsAgo = new Date(Date.now() - 28512000000); // ~330 days
    expect(formatRelativeTime(elevenMonthsAgo)).toBe("11 months ago");
  });

  test("returns years for dates more than 12 months ago", () => {
    const oneYearAgo = new Date(Date.now() - 31536000000); // ~365 days
    expect(formatRelativeTime(oneYearAgo)).toBe("1 year ago");

    const twoYearsAgo = new Date(Date.now() - 63072000000); // ~730 days
    expect(formatRelativeTime(twoYearsAgo)).toBe("2 years ago");
  });

  test("handles string dates", () => {
    const dateString = new Date(Date.now() - 3600000).toISOString();
    expect(formatRelativeTime(dateString)).toBe("1 hour ago");
  });

  test("handles Date objects", () => {
    const date = new Date(Date.now() - 3600000);
    expect(formatRelativeTime(date)).toBe("1 hour ago");
  });
});

describe("formatAbsoluteTime", () => {
  test("formats date as absolute time string", () => {
    const date = new Date("2024-03-15T12:00:00Z");
    const formatted = formatAbsoluteTime(date);

    // The exact format depends on locale, but should contain month, day, and year
    expect(formatted).toMatch(/Mar/i);
    expect(formatted).toContain("15");
    expect(formatted).toContain("2024");
  });

  test("handles string dates", () => {
    const dateString = "2024-03-15T12:00:00Z";
    const formatted = formatAbsoluteTime(dateString);

    expect(formatted).toMatch(/Mar/i);
    expect(formatted).toContain("15");
    expect(formatted).toContain("2024");
  });

  test("formats different dates correctly", () => {
    const date1 = new Date("2023-01-01T00:00:00Z");
    const formatted1 = formatAbsoluteTime(date1);
    expect(formatted1).toMatch(/Jan/i);
    expect(formatted1).toContain("2023");

    const date2 = new Date("2023-12-31T23:59:59Z");
    const formatted2 = formatAbsoluteTime(date2);
    expect(formatted2).toMatch(/Dec/i);
    expect(formatted2).toContain("2023");
  });
});

describe("formatFullDateTime", () => {
  test("formats date with time for hover tooltips", () => {
    const date = new Date("2024-03-15T14:30:00Z");
    const formatted = formatFullDateTime(date);

    // Should contain month, day, year, hour, and minute
    expect(formatted).toMatch(/Mar/i);
    expect(formatted).toContain("15");
    expect(formatted).toContain("2024");
    // Time format will vary by locale/timezone
  });

  test("handles string dates", () => {
    const dateString = "2024-03-15T14:30:00Z";
    const formatted = formatFullDateTime(dateString);

    expect(formatted).toMatch(/Mar/i);
    expect(formatted).toContain("15");
    expect(formatted).toContain("2024");
  });
});

describe("formatShortRelativeTime", () => {
  test("returns 'now' for dates less than 60 seconds ago", () => {
    const now = new Date(Date.now() - 30000);
    expect(formatShortRelativeTime(now)).toBe("now");
  });

  test("returns short format for minutes", () => {
    const oneMinuteAgo = new Date(Date.now() - 60000);
    expect(formatShortRelativeTime(oneMinuteAgo)).toBe("1m");

    const thirtyMinutesAgo = new Date(Date.now() - 1800000);
    expect(formatShortRelativeTime(thirtyMinutesAgo)).toBe("30m");
  });

  test("returns short format for hours", () => {
    const oneHourAgo = new Date(Date.now() - 3600000);
    expect(formatShortRelativeTime(oneHourAgo)).toBe("1h");

    const twelveHoursAgo = new Date(Date.now() - 43200000);
    expect(formatShortRelativeTime(twelveHoursAgo)).toBe("12h");
  });

  test("returns short format for days", () => {
    const oneDayAgo = new Date(Date.now() - 86400000);
    expect(formatShortRelativeTime(oneDayAgo)).toBe("1d");

    const tenDaysAgo = new Date(Date.now() - 864000000);
    expect(formatShortRelativeTime(tenDaysAgo)).toBe("10d");
  });

  test("returns short format for months", () => {
    const oneMonthAgo = new Date(Date.now() - 2592000000);
    expect(formatShortRelativeTime(oneMonthAgo)).toBe("1mo");

    const sixMonthsAgo = new Date(Date.now() - 15552000000);
    expect(formatShortRelativeTime(sixMonthsAgo)).toBe("6mo");
  });

  test("returns short format for years", () => {
    const oneYearAgo = new Date(Date.now() - 31536000000);
    expect(formatShortRelativeTime(oneYearAgo)).toBe("1y");

    const threeYearsAgo = new Date(Date.now() - 94608000000);
    expect(formatShortRelativeTime(threeYearsAgo)).toBe("3y");
  });

  test("handles string dates", () => {
    const dateString = new Date(Date.now() - 3600000).toISOString();
    expect(formatShortRelativeTime(dateString)).toBe("1h");
  });
});
