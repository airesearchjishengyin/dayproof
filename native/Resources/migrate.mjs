import Database from 'better-sqlite3';
import { existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
const [source, target] = process.argv.slice(2);
if (!existsSync(join(target, 'dayproof.sqlite')) && existsSync(join(source, 'dayproof.sqlite'))) {
  mkdirSync(target, { recursive: true, mode: 0o700 });
  const db = new Database(join(source, 'dayproof.sqlite'), { readonly: true });
  await db.backup(join(target, 'dayproof.sqlite'));
  db.close();
  console.log('Copied legacy database with SQLite backup; original retained.');
}
