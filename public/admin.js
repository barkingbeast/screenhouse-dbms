let services,data,kind='movies',editing=null;
const $=s=>document.querySelector(s);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const price=p=>new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:2}).format(Number(p)/100);
const localTime=value=>{const d=new Date(value);return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
export function initAdmin(options){
 services=options;
 const nav=document.createElement('button');nav.className='nav';nav.dataset.tab='admin';nav.textContent='Admin';$('nav').append(nav);
 const section=document.createElement('section');section.id='admin';section.className='tab';section.hidden=true;
 section.innerHTML=`<div class="page-intro split-intro"><div><span class="section-step">Cinema operations</span><h1>The whole cinema.<br>In your hands.</h1><p>Manage the programme, prepare your screens, and set a price for every seat.</p></div><span class="admin-mode">Local demo admin · No sign-in</span></div><div class="admin-toolbar"><div class="admin-tabs" role="group" aria-label="Manage cinema"><button data-admin-kind="movies" aria-pressed="true">Movies</button><button data-admin-kind="screens" aria-pressed="false">Screens</button><button data-admin-kind="shows" aria-pressed="false">Shows & pricing</button></div><button id="admin-refresh">Refresh records ↻</button></div><div class="admin-workspace"><form id="admin-form" class="panel"></form><div class="admin-register"><div class="section-heading compact"><h2 id="admin-list-title">Movie programme</h2><span id="admin-count"></span></div><div id="admin-list"></div></div></div>`;
 $('main').append(section);
 section.querySelectorAll('[data-admin-kind]').forEach(b=>b.onclick=()=>{kind=b.dataset.adminKind;editing=null;render();});
 $('#admin-refresh').onclick=()=>loadAdmin().catch(e=>services.notice(e.message,true));
}
export async function loadAdmin(){data=await services.api('/admin/catalog');if(editing)editing=data[kind].find(x=>x.id===editing.id)||null;render();}
function field(label,name,type,value,extra=''){return `<label for="admin-${name}">${label}</label><input id="admin-${name}" name="${name}" type="${type}" value="${esc(value)}" ${extra}>`;}
function select(label,name,items,value){return `<label for="admin-${name}">${label}</label><select id="admin-${name}" name="${name}" required>${items.map(i=>`<option value="${i.id}" ${i.id===Number(value)?'selected':''}>${esc(i.title||i.name)}</option>`).join('')}</select>`;}
function render(){
 if(!data)return;
 document.querySelectorAll('[data-admin-kind]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.adminKind===kind)));
 const singular={movies:'movie',screens:'screen',shows:'show'}[kind],r=editing||{};
 let html=`<span class="section-step">${editing?'Editing #'+r.id:'New '+singular}</span><h2>${editing?'Edit':'Add'} ${singular}</h2>`;
 if(kind==='movies')html+=field('Movie title','title','text',r.title||'','required maxlength="120"')+field('Language','language','text',r.language||'English','required maxlength="40"')+`<div class="form-pair">${field('Runtime (minutes)','duration_minutes','number',r.duration_minutes||120,'required min="1" max="600"')}${field('Genre','genre','text',r.genre||'Drama','required maxlength="60"')}</div>`;
 if(kind==='screens')html+=field('Screen name','name','text',r.name||'','required maxlength="80"')+select('Theatre','theatre_id',data.theatres,r.theatre_id)+field('Seats per row','seats_per_row','number',editing?Math.floor(r.seat_count/3):10,editing?'disabled':'required min="4" max="12"')+`<p class="hint">Three rows: A · Standard, B · Premium, C · Recliner. ${editing?'Seat layouts are fixed after creation to preserve show inventory.':'Seats are created automatically when you save.'}</p>`;
 if(kind==='shows')html+=select('Movie','movie_id',data.movies,r.movie_id)+select('Screen','screen_id',data.screens,r.screen_id)+field('Show starts (your local time)','starts_at','datetime-local',localTime(r.starts_at||Date.now()+86400000),'required')+`<fieldset class="price-fields"><legend>Ticket prices · INR per seat</legend>${field('Standard','standard_price','number',r.prices?Number(r.prices.STANDARD)/100:250,'required min="0.01" max="100000" step="0.01"')}${field('Premium','premium_price','number',r.prices?Number(r.prices.PREMIUM)/100:350,'required min="0.01" max="100000" step="0.01"')}${field('Recliner','recliner_price','number',r.prices?Number(r.prices.RECLINER)/100:500,'required min="0.01" max="100000" step="0.01"')}</fieldset><p class="hint">${r.booking_count?'This show has ticket history: change prices or pause sales; keep the movie, screen and time.':'A new show gets every seat on its screen. Times must allow the movie runtime plus 15 minutes for cleanup.'} Existing tickets keep their original prices.</p>`;
 if(kind!=='screens')html+=`<label class="check-field"><input type="checkbox" name="is_active" ${r.is_active!==false?'checked':''}>Open for sales</label>`;
 html+=`<div class="admin-form-actions"><button class="primary" type="submit">${editing?'Save changes':'Add '+singular} <span aria-hidden="true">↗</span></button>${editing?'<button id="admin-cancel-edit" type="button">Cancel edit</button>':''}</div><p id="admin-feedback" class="hint" role="status"></p>`;
 $('#admin-form').innerHTML=html;
 if($('#admin-cancel-edit'))$('#admin-cancel-edit').onclick=()=>{editing=null;render();};
 $('#admin-form').onsubmit=submit;
 $('#admin-list-title').textContent={movies:'Movie programme',screens:'Your auditoriums',shows:'Show schedule'}[kind];
 $('#admin-count').textContent=data[kind].length+' records';
 $('#admin-list').innerHTML=data[kind].length?data[kind].map(item=>{
 let title,detail,meta;
 if(kind==='movies'){title=item.title;detail=`${item.language} / ${item.duration_minutes} min / ${item.genre}`;meta=`${item.show_count} shows · ${item.is_active?'Sales open':'Sales paused'}`;}
 if(kind==='screens'){title=item.name;detail=`${item.theatre} / ${item.seat_count} seats`;meta=`${item.show_count} shows · Standard / Premium / Recliner`;}
 if(kind==='shows'){title=item.title;detail=new Date(item.starts_at).toLocaleString('en-IN')+' / '+item.screen;meta=`Standard ${price(item.prices.STANDARD)} · Premium ${price(item.prices.PREMIUM)} · Recliner ${price(item.prices.RECLINER)}`;}
 return `<article class="admin-record"><span class="record-id">#${item.id}</span><div><h3>${esc(title)}</h3><p>${esc(detail)}</p><small>${esc(meta)}</small>${kind==='shows'?`<p>${item.booking_count} bookings · ${item.is_active?'Sales open':'Sales paused'}</p>`:''}</div><div class="record-actions"><button data-admin-edit="${item.id}">Edit</button><button data-admin-delete="${item.id}" aria-label="Delete ${esc(title)}">Delete</button></div></article>`;
 }).join(''):`<div class="empty-history"><h2>Room for your first ${singular}.</h2><p>Use the form to add it to PostgreSQL.</p></div>`;
 document.querySelectorAll('[data-admin-edit]').forEach(b=>b.onclick=()=>{editing=data[kind].find(x=>x.id===Number(b.dataset.adminEdit));render();$('#admin-form').scrollIntoView({block:'start',behavior:'instant'});$('#admin-form input')?.focus({preventScroll:true});});
 document.querySelectorAll('[data-admin-delete]').forEach(b=>b.onclick=async()=>{if(!confirm('Delete this unused '+singular+'? Records with show or booking history are protected.'))return;b.disabled=true;try{await services.api('/admin/'+kind+'/'+b.dataset.adminDelete,{method:'DELETE'});editing=null;await loadAdmin();await services.refresh();services.notice('Unused '+singular+' deleted.');}catch(e){services.notice(e.message,true);b.disabled=false;}});
}
async function submit(event){
 event.preventDefault();const form=event.target,button=form.querySelector('button[type="submit"]');button.disabled=true;button.textContent='Saving…';
 try{const payload=Object.fromEntries(new FormData(form));if(kind!=='screens')payload.is_active=form.elements.is_active.checked;
 if(kind==='shows')payload.starts_at=editing&&localTime(editing.starts_at)===payload.starts_at?editing.starts_at:new Date(payload.starts_at).toISOString();
 await services.api('/admin/'+kind+(editing?'/'+editing.id:''),{method:editing?'PUT':'POST',body:JSON.stringify(payload)});
 const message={movies:'Movie saved.',screens:'Screen saved. Its seats are ready.',shows:'Show and category prices saved.'}[kind];editing=null;await loadAdmin();await services.refresh();services.notice(message);
 }catch(error){$('#admin-feedback').textContent=error.message;$('#admin-feedback').className='admin-error';services.notice(error.message,true);button.disabled=false;button.textContent=editing?'Save changes':'Add '+{movies:'movie',screens:'screen',shows:'show'}[kind];}
}
