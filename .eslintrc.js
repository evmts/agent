module.exports = {
  extends: [
    'eslint:recommended',
    '@typescript-eslint/recommended',
    'plugin:astro/recommended'
  ],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    project: './tsconfig.json',
    tsconfigRootDir: __dirname
  },
  plugins: ['@typescript-eslint'],
  rules: {
    '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/prefer-nullish-coalescing': 'error',
    '@typescript-eslint/prefer-optional-chain': 'error',
    // Allow console usage for logging in this application
    'no-console': 'off',
    // Allow unused expressions for void operations
    '@typescript-eslint/no-unused-expressions': 'off',
    // Allow any usage for database rows and API responses
    '@typescript-eslint/no-explicit-any': 'off'
  },
  overrides: [
    {
      files: ['*.astro'],
      parser: 'astro-eslint-parser',
      parserOptions: {
        parser: '@typescript-eslint/parser',
        extraFileExtensions: ['.astro'],
        project: null // Disable TypeScript project for Astro files to avoid issues
      },
      rules: {
        // Disable TypeScript-specific rules for Astro files
        '@typescript-eslint/prefer-nullish-coalescing': 'off',
        '@typescript-eslint/prefer-optional-chain': 'off'
      }
    },
    {
      files: ['**/*.js', '**/*.mjs'],
      rules: {
        '@typescript-eslint/no-var-requires': 'off'
      }
    }
  ],
  env: {
    node: true,
    es6: true,
    browser: true
  },
  ignorePatterns: [
    'dist/',
    'node_modules/',
    '.astro/',
    '*.js',
    '*.mjs',
    'snapshot/',
    'native/',
    'tui/',
    'electric-ai-chat/',
    'gitea/'
  ]
};