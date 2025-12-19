import eslint from '@eslint/js';
import tseslint from '@typescript-eslint/eslint-plugin';
import tsparser from '@typescript-eslint/parser';
import astro from 'eslint-plugin-astro';
import astroParser from 'astro-eslint-parser';

export default [
  eslint.configs.recommended,
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: tsparser,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        project: './tsconfig.json'
      }
    },
    plugins: {
      '@typescript-eslint': tseslint
    },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/prefer-nullish-coalescing': 'off', // Disabled due to compatibility issues
      '@typescript-eslint/prefer-optional-chain': 'error',
      'no-console': 'off',
      '@typescript-eslint/no-unused-expressions': 'off',
      'no-undef': 'off' // TypeScript handles this
    }
  },
  {
    files: ['**/*.astro'],
    languageOptions: {
      parser: astroParser,
      parserOptions: {
        parser: tsparser,
        extraFileExtensions: ['.astro'],
        ecmaVersion: 'latest',
        sourceType: 'module'
      }
    },
    plugins: {
      astro: astro
    },
    rules: {
      ...astro.configs.base.rules,
      ...astro.configs.recommended.rules,
      'no-unused-vars': 'off',
      '@typescript-eslint/no-unused-vars': 'off' // Astro components often have unused props
    }
  },
  {
    ignores: [
      'dist/',
      'node_modules/',
      '.astro/',
      '*.js',
      '*.mjs',
      'snapshot/index.js',
      'snapshot/index.d.ts',
      'snapshot/**/*.node',
      'native/lib/**',
      'ui/env.d.ts'
    ]
  }
];