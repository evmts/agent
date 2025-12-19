import { Resend } from 'resend';

interface EmailConfig {
  from: string;
  resendApiKey?: string;
  smtpHost?: string;
  smtpPort?: number;
  smtpUser?: string;
  smtpPass?: string;
}

const config: EmailConfig = {
  from: process.env.EMAIL_FROM || 'noreply@plue.local',
  resendApiKey: process.env.RESEND_API_KEY,
  smtpHost: process.env.SMTP_HOST,
  smtpPort: process.env.SMTP_PORT ? parseInt(process.env.SMTP_PORT) : 587,
  smtpUser: process.env.SMTP_USER,
  smtpPass: process.env.SMTP_PASS,
};

// Initialize Resend if API key is provided
const resend = config.resendApiKey ? new Resend(config.resendApiKey) : null;

export interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

/**
 * Send email using Resend or SMTP
 */
export async function sendEmail(options: SendEmailOptions): Promise<void> {
  // Try Resend first if available
  if (resend) {
    try {
      await resend.emails.send({
        from: config.from,
        to: options.to,
        subject: options.subject,
        html: options.html,
        text: options.text,
      });
      return;
    } catch (error) {
      console.error('Failed to send email via Resend:', error);
      throw new Error('Failed to send email');
    }
  }

  // Fallback to SMTP if configured
  if (config.smtpHost && config.smtpUser && config.smtpPass) {
    try {
      // For production, implement SMTP sending here
      // For now, log the email to console in development
      if (process.env.NODE_ENV === 'development') {
        console.log('=== EMAIL (SMTP) ===');
        console.log('From:', config.from);
        console.log('To:', options.to);
        console.log('Subject:', options.subject);
        console.log('HTML:', options.html);
        if (options.text) {
          console.log('Text:', options.text);
        }
        console.log('===================');
        return;
      }
      
      // In production, implement actual SMTP sending
      throw new Error('SMTP implementation not available');
    } catch (error) {
      console.error('Failed to send email via SMTP:', error);
      throw new Error('Failed to send email');
    }
  }

  // Development fallback - log to console
  if (process.env.NODE_ENV === 'development') {
    console.log('=== EMAIL (DEVELOPMENT) ===');
    console.log('From:', config.from);
    console.log('To:', options.to);
    console.log('Subject:', options.subject);
    console.log('HTML:', options.html);
    if (options.text) {
      console.log('Text:', options.text);
    }
    console.log('===========================');
    return;
  }

  throw new Error('No email service configured');
}

/**
 * Send account activation email
 */
export async function sendActivationEmail(to: string, username: string, token: string): Promise<void> {
  const baseUrl = process.env.SITE_URL || 'http://localhost:4321';
  const activationUrl = `${baseUrl}/activate/${token}`;

  await sendEmail({
    to,
    subject: 'Activate your Plue account',
    html: `
      <h1>Welcome to Plue, ${username}!</h1>
      <p>Click the link below to activate your account:</p>
      <p><a href="${activationUrl}">${activationUrl}</a></p>
      <p>This link will expire in 24 hours.</p>
      <p>If you didn't create an account, you can safely ignore this email.</p>
    `,
    text: `Welcome to Plue, ${username}! Activate your account: ${activationUrl}`,
  });
}

/**
 * Send password reset email
 */
export async function sendPasswordResetEmail(to: string, username: string, token: string): Promise<void> {
  const baseUrl = process.env.SITE_URL || 'http://localhost:4321';
  const resetUrl = `${baseUrl}/password/reset/${token}`;

  await sendEmail({
    to,
    subject: 'Reset your Plue password',
    html: `
      <h1>Password Reset Request</h1>
      <p>Hi ${username},</p>
      <p>Click the link below to reset your password:</p>
      <p><a href="${resetUrl}">${resetUrl}</a></p>
      <p>This link will expire in 1 hour.</p>
      <p>If you didn't request a password reset, you can safely ignore this email.</p>
    `,
    text: `Password reset for ${username}: ${resetUrl}`,
  });
}