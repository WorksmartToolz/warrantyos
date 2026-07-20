#!/usr/bin/env node
// Regenerates types/database.ts from the local database schema.
// See scripts/README.md for usage and prerequisites.
//
// The generated Database type is produced by the Supabase CLI. The
// hand-authored convenience aliases below the marker line are
// preserved verbatim across regeneration; everything above the marker
// is overwritten from the current schema.

import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const OUTPUT = 'types/database.ts';
const MARKER = '// ─── HAND-AUTHORED CONVENIENCE ALIASES (preserved across regeneration) ───';

try {
  // Preserve the hand-authored alias tail from the existing file.
  let tail = '';
  try {
    const existing = readFileSync(OUTPUT, 'utf8');
    const idx = existing.indexOf(MARKER);
    if (idx !== -1) {
      tail = existing.slice(idx);
    } else {
      console.error(
        `Marker not found in ${OUTPUT}. Add the marker line above the ` +
        `convenience aliases before running, so the alias tail can be ` +
        `preserved. Aborting rather than discarding hand-authored types.`
      );
      process.exit(1);
    }
  } catch {
    console.error(
      `${OUTPUT} does not exist or is unreadable. Aborting rather than ` +
      `generating without preserving the alias tail.`
    );
    process.exit(1);
  }

  console.log('Generating Database type from local database...');
  const generated = execSync('supabase gen types typescript --local', {
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
  });

  const contents = generated.trimEnd() + '\n\n' + tail;
  writeFileSync(OUTPUT, contents);
  console.log(`Wrote ${OUTPUT} (${contents.length} bytes).`);
} catch (err) {
  console.error('Type generation failed:', err.message);
  process.exit(1);
}
