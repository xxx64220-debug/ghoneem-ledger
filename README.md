# Ghoneem Ledger

Mobile-first private tutoring ledger. GitHub Pages serves only the app interface; financial records live in isolated `gl_` tables in Supabase. Sign in with the existing center-finance owner account. There is no student signup and no data access before sign-in.

## Publish

Enable GitHub Pages under **Settings → Pages**, with **Deploy from a branch**, **main**, **/docs**. The folder supports the `/ghoneem-ledger/` project path. No build or repository secrets are needed.

## Security and isolation

The Supabase Edge bridge verifies the authenticated user using Supabase Auth and permits only the designated owner. It only routes to ledger tables/functions and the dedicated private receipt bucket. Existing center-finance tables, triggers, users, passwords and policies are unchanged. Both apps share project resources and the existing owner identity. Logout affects only this login session.

The public configuration contains a publishable key, never a service key or bridge secret. Database permissions deny direct anonymous or ordinary authenticated access to the ledger. The Edge runtime owns the privileged connection and performs authorization before every request. GitHub hosts code, not financial records.

The original Sites deployment failed to start because its configuration contained literal backslash-n characters between JavaScript declarations. This version uses valid module syntax and tests every JavaScript file, including imported configuration. It also has request timeouts and a startup error message.

## Features

Students, groups, package/per-session/monthly billing, attendance with cancellation and credit restoration, payments/refunds, adjustments, business/personal expenses, private receipts, recurring expenses, reports, WhatsApp reminder handoff, printable statements and CSV backups.

## Tests

`node tests/static.mjs` and `node tests/reports.test.cjs`. The rollback-only `tests/ledger.sql` verifies database money rules. Never apply database files to the math portal or another app's tables.

## Backend

`server/bridge.ts` is deployed as `ghoneem-ledger-bridge` in the existing finance Supabase project. The only browser origin currently allowed is `https://xxx64220-debug.github.io`. Add a custom domain to that allowlist before moving the frontend there. Database definitions live under `db/`; already-applied schema should not be re-run.
