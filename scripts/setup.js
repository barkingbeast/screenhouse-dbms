import pg from 'pg';
import {readFile} from 'node:fs/promises';
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});
try {
 const exists=await pool.query("SELECT to_regclass('public.customers') AS t");
 if(exists.rows[0].t) console.log('Schema already exists; existing data preserved.');
 else {for(const f of ['001_schema.sql','002_seed.sql']) {await pool.query(await readFile(new URL('../db/'+f,import.meta.url),'utf8'));console.log('Applied '+f);}}
 const ledger=await pool.query("SELECT to_regclass('public.ledger_transactions') AS t");
 if(!ledger.rows[0].t){await pool.query(await readFile(new URL('../db/004_ledger.sql',import.meta.url),'utf8'));console.log('Applied 004_ledger.sql; historical payments backfilled.');}
 else console.log('Ledger already exists; journals preserved.');
 const pricing=await pool.query("SELECT to_regclass('public.show_prices') AS t");
 if(!pricing.rows[0].t){await pool.query(await readFile(new URL('../db/006_admin_pricing.sql',import.meta.url),'utf8'));console.log('Applied 006_admin_pricing.sql; original ticket prices preserved.');}
 else console.log('Admin pricing already exists.');
} finally {await pool.end();}
