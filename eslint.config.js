import eslint from '@eslint/js';
import tseslint from '@typescript-eslint/eslint-plugin';
import tsparser from '@typescript-eslint/parser';
import astro from 'eslint-plugin-astro';

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
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      '@typescript-eslint/prefer-optional-chain': 'error',
      'no-console': 'off',
      '@typescript-eslint/no-unused-expressions': 'off'
    }
  },
  {
    files: ['**/*.astro'],
    languageOptions: {
      parser: astro.parser,
      parserOptions: {
        parser: tsparser,
        extraFileExtensions: ['.astro']
      }
    },
    plugins: {
      astro: astro
    },
    rules: {
      ...astro.configs.recommended.rules
    }
  },
  {
    ignores: [
      'dist/',
      'node_modules/',
      '.astro/',
      '*.js',
      '*.mjs',
      'snapshot/index.js'
    ]
  }
];