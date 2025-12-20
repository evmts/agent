/**
 * Client-side toast notification utility
 * Usage:
 *   window.toast.success("Operation completed");
 *   window.toast.error("Something went wrong");
 *   window.toast.info("Information message");
 *   window.toast.warning("Warning message");
 */

type ToastType = 'success' | 'error' | 'warning' | 'info';

interface ToastOptions {
  duration?: number;
  id?: string;
}

let toastId = 0;

function createToast(type: ToastType, message: string, options: ToastOptions = {}) {
  const container = document.getElementById('toast-container');
  if (!container) {
    console.error('Toast container not found');
    return;
  }

  const id = options.id || `toast-${++toastId}`;
  const duration = options.duration ?? 5000;

  // Create toast element
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.setAttribute('data-toast-id', id);
  toast.setAttribute('role', 'alert');
  toast.setAttribute('aria-live', 'polite');

  // Icons for each type
  const icons = {
    success: '✓',
    error: '✕',
    warning: '!',
    info: 'i',
  };

  // Build toast HTML
  toast.innerHTML = `
    <div class="toast-icon">${icons[type]}</div>
    <div class="toast-message">${escapeHtml(message)}</div>
    <button class="toast-close" aria-label="Dismiss">✕</button>
  `;

  // Add close button handler
  const closeBtn = toast.querySelector('.toast-close');
  closeBtn?.addEventListener('click', () => removeToast(toast));

  // Add to container
  container.appendChild(toast);

  // Auto-remove after duration
  if (duration > 0) {
    setTimeout(() => removeToast(toast), duration);
  }

  return id;
}

function removeToast(toast: HTMLElement) {
  // Add removing class for exit animation
  toast.classList.add('removing');

  // Remove after animation completes
  setTimeout(() => {
    toast.remove();
  }, 200);
}

function escapeHtml(text: string): string {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Public API
export const toast = {
  success: (message: string, options?: ToastOptions) => createToast('success', message, options),
  error: (message: string, options?: ToastOptions) => createToast('error', message, options),
  warning: (message: string, options?: ToastOptions) => createToast('warning', message, options),
  info: (message: string, options?: ToastOptions) => createToast('info', message, options),
};

// Make available globally
if (typeof window !== 'undefined') {
  (window as any).toast = toast;
}

// Type augmentation for window
declare global {
  interface Window {
    toast: typeof toast;
  }
}
