import { describe, test, expect } from 'vitest';
import { matchRoute } from './router';

describe('matchRoute', () => {
  describe('API routes', () => {
    test('routes API paths to origin', () => {
      const result = matchRoute('/api/users');
      expect(result.type).toBe('origin');
    });

    test('routes nested API paths to origin', () => {
      const result = matchRoute('/api/repos/owner/name/issues');
      expect(result.type).toBe('origin');
    });
  });

  describe('static assets', () => {
    test('routes _astro paths to origin', () => {
      const result = matchRoute('/_astro/bundle.js');
      expect(result.type).toBe('origin');
    });

    test('routes CSS files to origin', () => {
      const result = matchRoute('/styles/main.css');
      expect(result.type).toBe('origin');
    });

    test('routes JS files to origin', () => {
      const result = matchRoute('/scripts/app.js');
      expect(result.type).toBe('origin');
    });

    test('routes favicon to origin', () => {
      const result = matchRoute('/favicon.ico');
      expect(result.type).toBe('origin');
    });
  });

  describe('edge routes', () => {
    test('routes /login to edge with login handler', () => {
      const result = matchRoute('/login');
      expect(result.type).toBe('edge');
      expect(result.handler).toBe('login');
    });

    test('routes /register to edge with register handler', () => {
      const result = matchRoute('/register');
      expect(result.type).toBe('edge');
      expect(result.handler).toBe('register');
    });
  });

  describe('git routes (require origin)', () => {
    test('routes repository home to origin', () => {
      const result = matchRoute('/owner/repo');
      expect(result.type).toBe('origin');
    });

    test('routes tree browser to origin', () => {
      const result = matchRoute('/owner/repo/tree/main/src');
      expect(result.type).toBe('origin');
    });

    test('routes blob viewer to origin', () => {
      const result = matchRoute('/owner/repo/blob/main/README.md');
      expect(result.type).toBe('origin');
    });

    test('routes commit history to origin', () => {
      const result = matchRoute('/owner/repo/commits/main');
      expect(result.type).toBe('origin');
    });

    test('routes branch management to origin', () => {
      const result = matchRoute('/owner/repo/branches');
      expect(result.type).toBe('origin');
    });

    test('routes PR files to origin', () => {
      const result = matchRoute('/owner/repo/pulls/123/files');
      expect(result.type).toBe('origin');
    });

    test('routes new repo page to origin', () => {
      const result = matchRoute('/new');
      expect(result.type).toBe('origin');
    });
  });

  describe('default handling', () => {
    test('routes unknown paths to origin', () => {
      const result = matchRoute('/some/unknown/path');
      expect(result.type).toBe('origin');
    });
  });
});
