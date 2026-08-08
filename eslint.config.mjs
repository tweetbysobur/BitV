import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({ baseDirectory: __dirname });

const config = [
  {
    ignores: [
      'node_modules/**',
      '.next/**',
      'out/**',
      'build/**',
      'legacy/**',
      'next-env.d.ts',
      // Foundry project: Solidity is linted by `forge fmt`/`forge lint`, and
      // `contracts/lib/**` is vendored third-party dependency source
      // (OpenZeppelin's own Hardhat configs, docs tooling, and Certora
      // scripts) that this project neither authors nor ships.
      'contracts/**',
      // Generated from Foundry artifacts by `npm run abis` — reformatting a
      // generated file just creates churn on every regeneration.
      'src/lib/contracts/abis/**',
    ],
  },

  ...compat.extends(
    'next/core-web-vitals',
    'next/typescript',
    'plugin:@typescript-eslint/recommended',
    'prettier',
  ),

  {
    rules: {
      // ---------------------------------------------------------------------
      // Financial-correctness rules. These are errors, not warnings, because
      // each one maps to a class of bug that costs users money.
      // ---------------------------------------------------------------------

      // Prevent implicit bigint -> number coercion. All on-chain amounts are
      // bigint end-to-end; a float in a balance path is a precision defect.
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unsafe-assignment': 'off', // requires type-aware linting; enabled in CI config
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],

      // Number formatting must go through lib/format so precision and locale
      // handling stay centralised rather than being reimplemented per feature.
      'no-restricted-properties': [
        'error',
        {
          object: 'Number',
          property: 'parseFloat',
          message:
            'Do not parse financial values as floats. Use bigint helpers in @/lib/format.',
        },
      ],
      'no-restricted-globals': [
        'error',
        {
          name: 'parseFloat',
          message:
            'Do not parse financial values as floats. Use bigint helpers in @/lib/format.',
        },
      ],

      // Console noise is a production smell; warn/error are permitted for
      // genuine operational signalling.
      'no-console': ['error', { allow: ['warn', 'error'] }],

      'react/jsx-curly-brace-presence': [
        'error',
        { props: 'never', children: 'never' },
      ],
      'react-hooks/exhaustive-deps': 'error',
    },
  },

  // Config files legitimately need default exports and loose typing.
  {
    files: ['*.config.{ts,mjs,js}', 'src/config/**/*.ts'],
    rules: { 'no-restricted-exports': 'off' },
  },

  // Build scripts are CLI tools whose entire output IS stdout — the
  // no-console rule exists to keep debug logging out of the shipped app,
  // which does not apply to something invoked as `npm run abis`.
  {
    files: ['scripts/**/*.{mjs,js,ts}'],
    rules: { 'no-console': 'off' },
  },
];

export default config;
