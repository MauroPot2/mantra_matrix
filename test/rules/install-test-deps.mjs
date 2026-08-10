import { execFileSync } from 'node:child_process';

// Keep Firebase emulator tooling out of the Flutter application's dependency
// graph. CI installs the latest compatible rule-testing toolchain inside this
// isolated test package only.
execFileSync(
  'npm',
  [
    'install',
    '--no-package-lock',
    '--no-save',
    '--ignore-scripts',
    '@firebase/rules-unit-testing@latest',
    'firebase@latest',
    'firebase-tools@latest',
  ],
  {
    stdio: 'inherit',
    env: process.env,
  },
);
