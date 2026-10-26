import http from 'node:http';
import {readFile} from 'node:fs/promises';
import pg from 'pg';
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL,max:10});
const port=Number(process.env.PORT||3035);
const rows=async(sql,args=[]) => (await pool.query(sql,args)).rows;
const send=(res,status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
async function body(req){let data='';for await(const chunk of req){data+=chunk;if(data.length>20000)throw Error('Request too large');}return JSON.parse(data||'{}');}
const bookingSql=`SELECT b.*,c.name AS customer,m.title,sh.starts_at,sc.name AS screen, (SELECT string_agg(s.row_label||s.seat_number,', ' ORDER BY s.row_label,s.seat_number) FROM booking_seats bs JOIN seats s ON s.id=bs.seat_id WHERE bs.booking_id=b.id) AS seats FROM bookings b JOIN customers c ON c.id=b.customer_id JOIN shows sh ON sh.id=b.show_id JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id`;
const queries={
 customers:{label:'All customers',sql:'SELECT id, name, email, created_at FROM customers ORDER BY id DESC'},
 shows:{label:'Shows with movie and theatre (JOIN)',sql:'SELECT sh.id, m.title, t.name AS theatre, sc.name AS screen, sh.starts_at, sh.price_paise / 100.0 AS price_rupees FROM shows sh JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id JOIN theatres t ON t.id=sc.theatre_id ORDER BY sh.starts_at'},
 tickets:{label:'Bookings and customer details (JOIN)',sql:bookingSql+' ORDER BY b.id DESC'},
 occupancy:{label:'Seat occupancy (view + GROUP BY)',sql:'SELECT * FROM show_occupancy ORDER BY show_id'},
 revenue:{label:'Revenue after refunds (aggregate)',sql:'SELECT title, net_paise / 100.0 AS net_rupees FROM movie_revenue ORDER BY net_paise DESC'},
 payments:{label:'Payment and refund history',sql:'SELECT * FROM payments ORDER BY id DESC'},
 ledger:{label:'Ledger: debits and credits',sql:'SELECT transaction_id,booking_id,kind,reverses_id,account,round(debit_paise/100.0,2) AS debit_rupees,round(credit_paise/100.0,2) AS credit_rupees FROM ledger_journal ORDER BY transaction_id DESC,account'},
 balances:{label:'Ledger: account balances',sql:"SELECT code,name,round(balance_paise/100.0,2) AS balance_rupees,CASE WHEN balance_paise>=0 THEN 'Debit' ELSE 'Credit' END AS balance_side FROM ledger_balances ORDER BY code"},
 audit:{label:'Ledger: balance audit',sql:'SELECT transaction_id,booking_id,kind,entry_count,net_paise,balanced FROM ledger_audit ORDER BY transaction_id DESC'},
 reconciliation:{label:'Ledger: payment reconciliation',sql:'SELECT * FROM ledger_reconciliation ORDER BY payment_id DESC'},
 unbooked:{label:'Movies without bookings (NOT EXISTS)',sql:'SELECT m.title FROM movies m WHERE NOT EXISTS (SELECT 1 FROM shows sh JOIN bookings b ON b.show_id=sh.id WHERE sh.movie_id=m.id)'},
 tables:{label:'Inspect table columns',sql:"SELECT table_name,column_name,data_type FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position"}
};
const staticFiles={'/':['index.html','text/html'],'/app.js':['app.js','text/javascript'],'/style.css':['style.css','text/css'],'/fonts/outfit-regular.ttf':['fonts/outfit-regular.ttf','font/ttf'],'/fonts/outfit-semibold.ttf':['fonts/outfit-semibold.ttf','font/ttf'],'/fonts/prata.ttf':['fonts/prata.ttf','font/ttf']};
http.createServer(async(req,res)=>{
 try {
 const url=new URL(req.url,'http://localhost');const path=url.pathname;
 if(req.method==='POST'&&req.headers.origin&& ![`http://localhost:${port}`,`http://127.0.0.1:${port}`].includes(req.headers.origin))return send(res,403,{error:'Use the local application origin.'});
 if(req.method==='GET'&&staticFiles[path]){const [f,type]=staticFiles[path];res.writeHead(200,{'Content-Type':type+'; charset=utf-8','X-Content-Type-Options':'nosniff'});return res.end(await readFile(new URL('../public/'+f,import.meta.url)));}
 if(req.method==='GET'&&path==='/api/health')return send(res,200,(await rows('SELECT current_database() AS database, version(), now() AS server_time'))[0]);
 if(req.method==='GET'&&path==='/api/customers')return send(res,200,await rows('SELECT * FROM customers ORDER BY id DESC'));
 if(req.method==='POST'&&path==='/api/customers'){const b=await body(req);if(typeof b.name!=='string'||typeof b.email!=='string')return send(res,400,{error:'Enter a name and email.'});return send(res,201,(await rows('INSERT INTO customers(name,email) VALUES($1,$2) RETURNING *',[b.name.trim(),b.email.trim().toLowerCase()]))[0]);}
 if(req.method==='GET'&&path==='/api/shows')return send(res,200,await rows(`SELECT sh.*,m.title,m.language,m.genre,m.duration_minutes,sc.name AS screen,t.name AS theatre,o.available_seats FROM shows sh JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id JOIN theatres t ON t.id=sc.theatre_id JOIN show_occupancy o ON o.show_id=sh.id WHERE sh.starts_at>now() ORDER BY sh.starts_at`));
 if(req.method==='GET'&&/^\/api\/shows\/\d+\/seats$/.test(path))return send(res,200,await rows('SELECT s.id,s.row_label,s.seat_number,ss.booking_id FROM show_seats ss JOIN seats s ON s.id=ss.seat_id WHERE ss.show_id=$1 ORDER BY s.row_label,s.seat_number',[path.split('/')[3]]));
 if(req.method==='GET'&&path==='/api/bookings'){const id=url.searchParams.get('customer_id');return send(res,200,await rows(bookingSql+(id?' WHERE b.customer_id=$1':'')+' ORDER BY b.id DESC',id?[id]:[]));}
 if(req.method==='POST'&&path==='/api/bookings'){const b=await body(req);const result=await rows('SELECT book_ticket($1,$2,$3::integer[],$4) AS id',[b.customer_id,b.show_id,b.seat_ids,b.request_key]);return send(res,201,(await rows(bookingSql+' WHERE b.id=$1',[result[0].id]))[0]);}
 if(req.method==='POST'&&/^\/api\/bookings\/\d+\/cancel$/.test(path)){const b=await body(req);return send(res,200,(await rows('SELECT cancel_booking($1,$2) AS id',[path.split('/')[3],b.customer_id]))[0]);}
 if(req.method==='GET'&&path==='/api/review')return send(res,200,queries);
 if(req.method==='POST'&&path==='/api/query'){
   const b=await body(req);if(typeof b.sql!=='string'||!/^\s*(SELECT|WITH|EXPLAIN)\b/i.test(b.sql))return send(res,400,{error:'The review console accepts a single SELECT, WITH, or EXPLAIN query. Use psql for INSERT or booking functions.'});
   const client=await pool.connect();try{await client.query('BEGIN READ ONLY');await client.query("SET LOCAL statement_timeout='2500ms'");const result=await client.query({text:b.sql,queryMode:'extended'});await client.query('ROLLBACK');return send(res,200,{rows:result.rows.slice(0,200),fields:result.fields.map(x=>x.name),rowCount:result.rowCount});}
   catch(e){
     if(e.code==='42P01')return send(res,400,{error:e.message.includes('"customer"')?'The table "customer" does not exist. Use "customers" (plural): SELECT * FROM customers;':e.message+'. Check table names using the "Inspect table columns" example.',code:e.code});
     if(e.code?.startsWith('42'))return send(res,400,{error:e.message,code:e.code});
     throw e;
   }finally{try{await client.query('ROLLBACK');}finally{client.release();}}
 }
 send(res,404,{error:'Not found'});
 }catch(e){console.error(e.code||'',e.message);const known=['P0001','23505','23514','23502','22P02','23503','25006','42601','57014'].includes(e.code);send(res,known? (e.code==='23505'||e.message.includes('unavailable')?409:400):500,{error:e.code==='23505'?'This email or request already exists.':known?e.message:'Request failed. Check the server console.'});}
}).listen(port,'127.0.0.1',()=>console.log(`Screenhouse running at http://localhost:${port}`));
