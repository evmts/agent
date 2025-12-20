/**
 * Date utility functions for issue due dates
 */

export interface DueDateStatus {
  isOverdue: boolean;
  daysUntilDue: number;
  relativeText: string;
  colorClass: 'due-future' | 'due-soon' | 'due-overdue';
}

/**
 * Calculate the status of a due date
 */
export function getDueDateStatus(dueDate: string | Date | null): DueDateStatus | null {
  if (!dueDate) return null;

  const due = new Date(dueDate);
  const now = new Date();

  // Reset time to midnight for accurate day comparison
  due.setHours(0, 0, 0, 0);
  now.setHours(0, 0, 0, 0);

  const diffMs = due.getTime() - now.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  const isOverdue = diffDays < 0;
  const daysUntilDue = Math.abs(diffDays);

  let relativeText: string;
  let colorClass: 'due-future' | 'due-soon' | 'due-overdue';

  if (isOverdue) {
    if (daysUntilDue === 0) {
      relativeText = 'due today';
    } else if (daysUntilDue === 1) {
      relativeText = 'overdue by 1 day';
    } else {
      relativeText = `overdue by ${daysUntilDue} days`;
    }
    colorClass = 'due-overdue';
  } else if (diffDays === 0) {
    relativeText = 'due today';
    colorClass = 'due-soon';
  } else if (diffDays === 1) {
    relativeText = 'due tomorrow';
    colorClass = 'due-soon';
  } else if (diffDays <= 3) {
    relativeText = `due in ${diffDays} days`;
    colorClass = 'due-soon';
  } else if (diffDays <= 7) {
    relativeText = `due in ${diffDays} days`;
    colorClass = 'due-future';
  } else {
    relativeText = `due in ${diffDays} days`;
    colorClass = 'due-future';
  }

  return {
    isOverdue,
    daysUntilDue,
    relativeText,
    colorClass,
  };
}

/**
 * Format a date as a readable string (e.g., "Jan 15, 2025")
 */
export function formatDate(date: string | Date | null): string {
  if (!date) return '';

  const d = new Date(date);
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

/**
 * Format a date for use in an HTML date input (YYYY-MM-DD)
 */
export function formatDateForInput(date: string | Date | null): string {
  if (!date) return '';

  const d = new Date(date);
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
}

/**
 * Parse a date from an HTML date input (YYYY-MM-DD) to ISO string
 */
export function parseDateFromInput(dateString: string): string | null {
  if (!dateString) return null;

  try {
    const date = new Date(dateString);
    return date.toISOString();
  } catch {
    return null;
  }
}
