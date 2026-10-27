// Local academic admin tools. All values are parameterized; writes share one connection.
function fail(message,status=400){const error=new Error(message);error.status=status;throw error;}
function text(value,label,max=100){if(typeof value!=='string'||!value.trim()||value.trim().length>max)fail(`${label} is required (maximum ${max} characters).`);return value.trim();}
function integer(value,label,min=1,max=2147483647){if(!Number.isInteger(Number(value))||Number(value)<min||Number(value)>max)fail(`${label} must be between ${min} and ${max}.`);return Number(value);}
export function rupees(value){const str=String(value??'');if(!/^\d+(\.\d{1,2})?$/.test(str))fail('Enter a positive price with at most two decimal places.');const [whole,fraction='']=str.split('.');const amount=Number(whole)*100+Number(fraction.padEnd(2,'0'));return integer(amount,'Price in paise',1,10000000);}
async function transaction(pool,work){const c=await pool.connect();try{await c.query('BEGIN');const result=await work(c);await c.query('COMMIT');return result;}catch(error){await c.query('ROLLBACK');throw error;}finally{c.release();}}
export async function catalog(pool){const [movies,screens,shows,theatres,categories]=await Promise.all([
 pool.query('SELECT m.*,(SELECT count(*)::integer FROM shows WHERE movie_id=m.id) AS show_count FROM movies m ORDER BY id'),
 pool.query('SELECT sc.*,t.name AS theatre,(SELECT count(*)::integer FROM seats WHERE screen_id=sc.id) AS seat_count,(SELECT count(*)::integer FROM shows WHERE screen_id=sc.id) AS show_count FROM screens sc JOIN theatres t ON t.id=sc.theatre_id ORDER BY sc.id'),
 pool.query(`SELECT sh.*,m.title,sc.name AS screen,(SELECT count(*)::integer FROM bookings WHERE show_id=sh.id) AS booking_count,(SELECT jsonb_object_agg(c.code,p.price_paise::text) FROM show_prices p JOIN seat_categories c ON c.id=p.category_id WHERE p.show_id=sh.id) AS prices FROM shows sh JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id ORDER BY sh.starts_at`),
 pool.query('SELECT * FROM theatres ORDER BY id'),pool.query('SELECT * FROM seat_categories ORDER BY sort_order')
 ]);return {movies:movies.rows,screens:screens.rows,shows:shows.rows,theatres:theatres.rows,categories:categories.rows};}
export async function saveMovie(pool,b,id){
 const values=[text(b.title,'Title',120),text(b.language,'Language',40),integer(b.duration_minutes,'Runtime',1,600),text(b.genre,'Genre',60),b.is_active!==false];
 return transaction(pool,async c=>{
 if(id){const old=(await c.query('SELECT * FROM movies WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!old)fail('Movie not found.',404);
 if(old.duration_minutes!==values[2]&&(await c.query('SELECT 1 FROM shows WHERE movie_id=$1 LIMIT 1',[id])).rowCount)fail('Runtime cannot change while this movie has scheduled shows.');
 return (await c.query('UPDATE movies SET title=$1,language=$2,duration_minutes=$3,genre=$4,is_active=$5 WHERE id=$6 RETURNING *',[...values,id])).rows[0];}
 return (await c.query('INSERT INTO movies(title,language,duration_minutes,genre,is_active) VALUES($1,$2,$3,$4,$5) RETURNING *',values)).rows[0];});
}
export async function saveScreen(pool,b,id){
 const name=text(b.name,'Screen name',80),theatre=integer(b.theatre_id,'Theatre');
 return transaction(pool,async c=>{
 if(id){const old=(await c.query('SELECT * FROM screens WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!old)fail('Screen not found.',404);
 if(theatre!==old.theatre_id&&(await c.query('SELECT 1 FROM shows WHERE screen_id=$1 LIMIT 1',[id])).rowCount)fail('A screen with shows cannot be moved to another theatre.');
 return (await c.query('UPDATE screens SET name=$1,theatre_id=$2 WHERE id=$3 RETURNING *',[name,theatre,id])).rows[0];}
 const count=integer(b.seats_per_row,'Seats per row',4,12);
 const sc=(await c.query('INSERT INTO screens(theatre_id,name) VALUES($1,$2) RETURNING *',[theatre,name])).rows[0];
 await c.query("INSERT INTO seats(screen_id,row_label,seat_number,category_id) SELECT $1,chr(64+c.sort_order),n,c.id FROM seat_categories c CROSS JOIN generate_series(1,$2::integer) n ORDER BY c.sort_order,n",[sc.id,count]);
 return sc;});
}
export async function saveShow(pool,b,id){
 const movie=integer(b.movie_id,'Movie'),screen=integer(b.screen_id,'Screen');
 const starts=new Date(b.starts_at);if(!b.starts_at||!Number.isFinite(starts.getTime())||starts.getTime()<=Date.now())fail('Choose a future show time.');
 const prices={STANDARD:rupees(b.standard_price),PREMIUM:rupees(b.premium_price),RECLINER:rupees(b.recliner_price)};
 if(prices.STANDARD>prices.PREMIUM||prices.PREMIUM>prices.RECLINER)fail('Use Standard ≤ Premium ≤ Recliner pricing.');
 return transaction(pool,async c=>{
 const m=(await c.query('SELECT * FROM movies WHERE id=$1 FOR SHARE',[movie])).rows[0];if(!m)fail('Movie not found.',404);
 const initial=id?(await c.query('SELECT * FROM shows WHERE id=$1',[id])).rows[0]:null;if(id&&!initial)fail('Show not found.',404);
 const locks=await c.query('SELECT id FROM screens WHERE id=ANY($1::integer[]) ORDER BY id FOR UPDATE',[[...new Set([screen,initial?.screen_id].filter(Boolean))]]);
 if(!locks.rows.some(x=>x.id===screen))fail('Screen not found.',404);
 if(!(await c.query('SELECT 1 FROM seats WHERE screen_id=$1 LIMIT 1',[screen])).rowCount)fail('Add seats to the screen before scheduling a show.');
 if(initial){const old=(await c.query('SELECT * FROM shows WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!old||old.screen_id!==initial.screen_id)fail('This show changed. Refresh and try again.',409);
 const booked=(await c.query('SELECT 1 FROM bookings WHERE show_id=$1 LIMIT 1',[id])).rowCount;
 if(booked&&(old.movie_id!==movie||old.screen_id!==screen||new Date(old.starts_at).getTime()!==starts.getTime()))fail('This show has ticket history. Only prices and sales availability can change.');
 }
 const collision=await c.query(`SELECT sh.id FROM shows sh JOIN movies m ON m.id=sh.movie_id WHERE sh.screen_id=$1 AND ($2::integer IS NULL OR sh.id<>$2) AND sh.starts_at < $3::timestamptz+($4::integer+15)*interval '1 minute' AND sh.starts_at+(m.duration_minutes+15)*interval '1 minute' > $3::timestamptz LIMIT 1`,[screen,id||null,starts.toISOString(),m.duration_minutes]);
 if(collision.rowCount)fail(`This time overlaps show #${collision.rows[0].id} on the same screen, including 15 minutes for cleanup.`,409);
 let sh;if(id){if(initial.screen_id!==screen)await c.query('DELETE FROM show_seats WHERE show_id=$1',[id]);
 sh=(await c.query('UPDATE shows SET movie_id=$1,screen_id=$2,starts_at=$3,price_paise=$4,is_active=$5 WHERE id=$6 RETURNING *',[movie,screen,starts.toISOString(),prices.STANDARD,b.is_active!==false,id])).rows[0];
 if(initial.screen_id!==screen)await c.query('INSERT INTO show_seats(show_id,seat_id,screen_id) SELECT $1,id,screen_id FROM seats WHERE screen_id=$2',[id,screen]);}
 else {sh=(await c.query('INSERT INTO shows(movie_id,screen_id,starts_at,price_paise,is_active) VALUES($1,$2,$3,$4,$5) RETURNING *',[movie,screen,starts.toISOString(),prices.STANDARD,b.is_active!==false])).rows[0];await c.query('INSERT INTO show_seats(show_id,seat_id,screen_id) SELECT $1,id,screen_id FROM seats WHERE screen_id=$2',[sh.id,screen]);}
 for(const [code,amount] of Object.entries(prices))await c.query('UPDATE show_prices SET price_paise=$1 WHERE show_id=$2 AND category_id=(SELECT id FROM seat_categories WHERE code=$3)',[amount,sh.id,code]);
 return sh;
 });
}
export async function deleteEntity(pool,kind,id){
 return transaction(pool,async c=>{
 if(kind==='movies'){if(!(await c.query('SELECT id FROM movies WHERE id=$1 FOR UPDATE',[id])).rowCount)fail('Movie not found.',404);if((await c.query('SELECT 1 FROM shows WHERE movie_id=$1 LIMIT 1',[id])).rowCount)fail('This movie has shows. Pause sales or remove its unused shows first.',409);await c.query('DELETE FROM movies WHERE id=$1',[id]);}
 else if(kind==='screens'){if(!(await c.query('SELECT id FROM screens WHERE id=$1 FOR UPDATE',[id])).rowCount)fail('Screen not found.',404);if((await c.query('SELECT 1 FROM shows WHERE screen_id=$1 LIMIT 1',[id])).rowCount)fail('This screen has shows and cannot be deleted.',409);await c.query('DELETE FROM seats WHERE screen_id=$1',[id]);await c.query('DELETE FROM screens WHERE id=$1',[id]);}
 else if(kind==='shows'){const prior=(await c.query('SELECT screen_id FROM shows WHERE id=$1',[id])).rows[0];if(!prior)fail('Show not found.',404);await c.query('SELECT id FROM screens WHERE id=$1 FOR UPDATE',[prior.screen_id]);const sh=(await c.query('SELECT * FROM shows WHERE id=$1 FOR UPDATE',[id])).rows[0];if(!sh||sh.screen_id!==prior.screen_id)fail('Show changed. Refresh and try again.',409);if((await c.query('SELECT 1 FROM bookings WHERE show_id=$1 LIMIT 1',[id])).rowCount)fail('A show with ticket or refund history cannot be deleted. Pause sales instead.',409);await c.query('DELETE FROM show_seats WHERE show_id=$1',[id]);await c.query('DELETE FROM show_prices WHERE show_id=$1',[id]);await c.query('DELETE FROM shows WHERE id=$1',[id]);}
 else fail('Unknown admin resource.',404);
 return {deleted:true,id};});
}
