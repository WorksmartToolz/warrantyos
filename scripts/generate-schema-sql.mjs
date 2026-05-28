#!/usr/bin/env node
// Regenerates supabase/schema.sql from the canonical migrations.
// See scripts/README.md for usage and prerequisites.

import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const OUTPUT = 'supabase/schema.sql';

try {
  console.log('Generating schema.sql from local database...');
  const schema = execSync('supabase db dump --local', {
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
  });
  writeFileSync(OUTPUT, schema);
  console.log(`Wrote ${OUTPUT} (${schema.length} bytes).`);
} catch (err) {
  console.error('Schema generation failed:', err.message);
  process.exit(1);
}
