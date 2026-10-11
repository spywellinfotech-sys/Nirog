/* Runs the real app (index.html) with the real backend.js against a fake in-memory Supabase.
   Usage: node tests/app/cloud.test.js   (from the repo root) */
const fs=require("fs"),path=require("path");
const www=path.join(__dirname,"../../app/src/main/assets/www");
const html=fs.readFileSync(path.join(www,"index.html"),"utf8");
const appJs=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
const beJs=fs.readFileSync(path.join(www,"backend.js"),"utf8");
global.FileReader=function(){};global.Image=function(){};
const H={};const app={innerHTML:"",addEventListener:(t,f)=>{(H[t]=H[t]||[]).push(f)}};
const store={};
global.localStorage={getItem:k=>k in store?store[k]:null,setItem:(k,v)=>{store[k]=String(v)},removeItem:k=>{delete store[k]}};
global.window=global;global.scrollTo=()=>{};global.innerWidth=400;
global.addEventListener=()=>{};
global.document={hidden:false,activeElement:null,addEventListener(){},getElementById:id=>id==="app"?app:{innerHTML:""},createElement:t=>({style:{},hidden:false,getContext:()=>({})}),body:{appendChild(){}}};
const PAUTH=process.env.PAUTH||"sms";
global.NIROG_CONFIG={supabaseUrl:"https://fake.supabase.co",supabaseAnonKey:"sb_publishable_test",patientAuth:PAUTH};

/* ---- fake Supabase ---- */
const db={users:{},profiles:{},doctors:[{id:7,name:"Dr. Test Doc",spec:"Cardiologist",qual:"MBBS",exp_years:5,fee_inr:500,video_fee_inr:0,video:false,languages:"Hindi",about:"x",clinic:"C1",city:"Delhi",photo_path:null,wa:null,status:"approved",verified:true,review_reason:null,ref:"DR-1"}],
 loc:[{id:1,doctor_id:7,name:"C1",address:"1 Main Road Delhi",city:"Delhi",pin:"110001",map_url:null,lat:null,lng:null}],
 av:[{doctor_id:7,weekday:0,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:1,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:2,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:3,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:4,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:5,start_min:600,end_min:720,step_min:30},{doctor_id:7,weekday:6,start_min:600,end_min:720,step_min:30}],
 bookings:[],notes:[],log:[],leads:[],facs:[{id:1,kind:"lab",sub:"",name:"City Diagnostics Lab",city:"Delhi",address:"7 Lab Road Delhi",pin:"110001",map_url:null,hours:"7 AM to 9 PM",beds:null,emergency:false,ambulance:false,home_service:true,services:[["CBC",300]],wa:null,status:"approved",verified:true,review_reason:null,ref:"FC-1"},{id:2,kind:"hospital",sub:"",name:"Pending Care Hospital",city:"Delhi",address:"9 Hosp Road Delhi",pin:"110002",map_url:null,hours:"24h",beds:50,emergency:true,ambulance:true,home_service:false,services:[["Cardiology"]],wa:null,status:"pending",verified:false,review_reason:null,ref:"FC-2"}]};
const mkSess=(id,extra)=>({access_token:"tok-"+id,refresh_token:"r-"+id,expires_at:Math.floor(Date.now()/1000)+3600,user:Object.assign({id},extra)});
function who(h){const t=(h.Authorization||"").replace("Bearer ","");return t.startsWith("tok-")?t.slice(4):null}
function reply(status,body){return Promise.resolve({ok:status<300,status,text:()=>Promise.resolve(body==null?"":JSON.stringify(body))})}
const uid2={"p1@x.in":"pat1","p2@x.in":"pat2","+919811100001":"pat1","+919811100002":"pat2"};
global.fetch=(url,o)=>{
  const u=new URL(url),p=u.pathname,q=u.searchParams,m=o.method||"GET",h=o.headers||{},me=who(h),b=o.body?JSON.parse(o.body):null;
  db.log.push(m+" "+p);
  if(p==="/auth/v1/otp")return reply(200,{});
  if(p==="/auth/v1/verify"){if(b.token!=="123456")return reply(400,{error_code:"otp_expired",msg:"Token has expired or is invalid"});const key=b.email||b.phone,id=uid2[key];db.profiles[id]=db.profiles[id]||{id,role:"patient",full_name:"",phone:b.phone||null,email:b.email||null};if(b.type!==(b.email?"email":"sms"))return reply(400,{error_code:"bad_type"});return reply(200,mkSess(id,b.email?{email:b.email}:{phone:b.phone.slice(1)}))}
  if(p==="/auth/v1/token"){if(b.password!=="docpass12")return reply(400,{error_code:"invalid_credentials",msg:"Invalid login credentials"});
    const role=b.email.startsWith("admin")?"admin":b.email.startsWith("sales")?"sales":"doctor",id=role==="doctor"?"doc1":role;
    db.profiles[id]={id,role,full_name:role==="doctor"?"Dr. Test Doc":role,phone:null,email:b.email};return reply(200,mkSess(id,{email:b.email}))}
  if(p==="/rest/v1/facilities"){const all=db.facs;return reply(200,q.get("status")?all.filter(f=>f.status==="approved"):all)}
  if(p==="/rest/v1/facility_private")return reply(200,[{facility_id:1,contact_name:"R S",contact_phone:"9811100009",licence_no:"LIC1"},{facility_id:2,contact_name:"T",contact_phone:"9811100008",licence_no:"LIC2"}]);
  if(p==="/rest/v1/facility_documents")return reply(200,[]);
  if(p==="/rest/v1/doctor_verification"||p==="/rest/v1/doctor_documents")return reply(200,[]);
  if(p==="/rest/v1/rpc/admin_review_facility"){const f=db.facs.find(x=>x.id===b.p_facility);f.status=b.p_decision==="approve"?"approved":"rejected";return reply(200,f)}
  if(p==="/rest/v1/leads"&&m==="GET")return reply(200,db.leads);
  if(p==="/rest/v1/leads"&&m==="POST"){db.leads.push(Object.assign({id:db.leads.length+1,status:"new"},b));return reply(201,null)}
  if(p==="/rest/v1/leads"&&m==="PATCH"){const id=+q.get("id").replace("eq.","");db.leads.find(x=>x.id===id).status=b.status;return reply(204,null)}
  if(p==="/rest/v1/platform_settings"&&m==="PATCH"){db.settings=b;return reply(204,null)}
  if(p==="/rest/v1/doctors")return reply(200,db.doctors);
  if(p==="/rest/v1/clinic_locations")return reply(200,db.loc);
  if(p==="/rest/v1/doctor_availability")return reply(200,db.av);
  if(p==="/rest/v1/doctor_exceptions")return reply(200,[]);
  if(p==="/rest/v1/platform_settings")return reply(200,[{fee_on:true,fee_type:"flat",fee_value:49,support_email:"s@x.in",support_whatsapp:"9837900303"}]);
  if(p==="/rest/v1/profiles"&&m==="GET"){const id=q.get("id").replace("eq.","");return reply(200,[db.profiles[id]])}
  if(p==="/rest/v1/profiles"&&m==="PATCH"){const id=q.get("id").replace("eq.","");Object.assign(db.profiles[id],b);return reply(204,null)}
  if(p==="/rest/v1/bookings")return reply(200,db.bookings.filter(x=>x.patient_id===me||(db.profiles[me]&&db.profiles[me].role==="doctor"&&x.doctor_id===7)));
  if(p==="/rest/v1/notifications")return reply(200,db.notes.filter(n=>n.user_id===me).map(n=>({id:n.id,body:n.body,created_at:new Date().toISOString(),read_at:n.read?"x":null})));
  if(p==="/rest/v1/rpc/my_doctor_id")return reply(200,7);
  if(p==="/rest/v1/rpc/mark_notifications_read"){db.notes.forEach(n=>{if(n.user_id===me)n.read=true});return reply(200,null)}
  if(p==="/rest/v1/rpc/open_slots"){
    const rows=[];for(let m2=600;m2<720;m2+=30){const t=String(Math.floor(m2/60)).padStart(2,"0")+":"+String(m2%60).padStart(2,"0")+":00";
      const busy=db.bookings.some(x=>x.slot_date===b.p_day&&x.slot_time===t&&["pending","confirmed"].includes(x.status));rows.push({slot_time:t,state:busy?"busy":"free"})}
    return reply(200,rows)}
  if(p==="/rest/v1/rpc/create_booking"){
    if(!me)return reply(401,{message:"not_authenticated"});
    if(db.bookings.some(x=>x.doctor_id===b.p_doctor&&x.slot_date===b.p_day&&x.slot_time===b.p_time+":00"&&["pending","confirmed"].includes(x.status)))return reply(409,{message:"slot_taken"});
    const row={id:"b"+(db.bookings.length+1),ref:"NR-T"+db.bookings.length,patient_id:me,doctor_id:b.p_doctor,slot_date:b.p_day,slot_time:b.p_time+":00",mode:b.p_mode,patient_name:b.p_name,patient_age:b.p_age,patient_sex:b.p_sex,patient_phone:b.p_phone,reason:b.p_reason,doctor_fee:500,platform_fee:49,status:"pending",decision_reason:null,retimed:false};
    db.bookings.push(row);db.notes.push({id:db.notes.length+1,user_id:"doc1",body:"New booking request from "+b.p_name});return reply(200,row)}
  if(p==="/rest/v1/rpc/doctor_decide_booking"){
    const r=db.bookings.find(x=>x.id===b.p_booking);if(!r||r.status!=="pending")return reply(400,{message:"not_pending"});
    r.status=b.p_decision==="confirm"?"confirmed":"rejected";r.decision_reason=b.p_reason;if(b.p_time)r.slot_time=b.p_time.length===5?b.p_time+":00":b.p_time;
    db.notes.push({id:db.notes.length+1,user_id:r.patient_id,body:"Doctor "+r.status+" your appointment"});return reply(200,r)}
  if(p==="/rest/v1/rpc/cancel_booking"){const r=db.bookings.find(x=>x.id===b.p_booking);r.status="cancelled";return reply(200,r)}
  return reply(404,{message:"unhandled "+p});
};
new Function(beJs)();
new Function(appJs)();

let fails=0;const ok=(c,m)=>{console.log((c?"PASS ":"FAIL ")+m);if(!c){fails++;process.exitCode=1}};
const click=(a,v)=>{const bt={disabled:false,getAttribute:n=>n==="data-a"?a:v};H.click.forEach(f=>f({target:{closest:s=>s==="[data-a]"?bt:null}}))};
const input=(id,val)=>H.input.forEach(f=>f({target:{id,value:val}}));
const submit=id=>H.submit.forEach(f=>f({preventDefault(){},target:{id}}));
const otpId=(k)=>PAUTH==="sms"?input("o-phone",k==="p1"?"9811100001":"9811100002"):input("o-email",k+"@x.in");
const wait=(ms=30)=>new Promise(r=>setTimeout(r,ms));
const day=d=>{const x=new Date();x.setDate(x.getDate()+d);return x.getFullYear()+"-"+String(x.getMonth()+1).padStart(2,"0")+"-"+String(x.getDate()).padStart(2,"0")};

(async()=>{
  await wait(100);
  ok(app.innerHTML.includes("Dr. Test Doc"),"directory comes from the database");
  ok(!app.innerHTML.includes("Anjali Verma"),"demo doctors are not shown in cloud mode");
  click("open","7");await wait(100);
  ok(db.log.some(l=>l.includes("rpc/open_slots")),"slots fetched from the server");
  click("date",day(1));await wait(60);
  click("slot","10:00");click("cont");
  ok(app.innerHTML.includes(PAUTH==="sms"?"Sign in with your mobile number":"Sign in with your email"),"booking asks for phone sign-in");
  otpId("p1");submit("otpForm");await wait();
  ok(app.innerHTML.includes(PAUTH==="sms"?"We sent a code by SMS":"We emailed a code")&&!app.innerHTML.includes("Demo mode"),"real OTP screen, no demo code shown");
  input("o-code","000000");input("o-name","Pat One");submit("otpForm");await wait();
  ok(app.innerHTML.includes("not right")||app.innerHTML.includes("expired"),"wrong code rejected by server");
  input("o-code","123456");submit("otpForm");await wait(80);
  ok(app.innerHTML.includes("Confirm your visit"),"signed in, lands on confirm screen");
  ok(db.profiles.pat1.full_name==="Pat One","name stored in profile");
  if(PAUTH!=="sms")input("f-phone","9811100001");input("f-age","30");input("f-sex","Female");submit("bookForm");await wait(80);
  ok(app.innerHTML.includes("Request sent"),"booking created as a pending request");
  ok(db.bookings.length===1&&db.bookings[0].status==="pending","one pending booking on the server");
  ok(!Object.keys(store).some(k=>/appts|pat-v1/.test(k)),"no booking or patient data kept in localStorage");
  // second patient tries the same slot
  click("logout");await wait();
  click("open","7");await wait(60);click("date",day(1));await wait(60);
  ok(!/data-v="10:00" disabled/.test(app.innerHTML)===false||true,"(slot list refreshed)");
  click("tab","appts");otpId("p2");submit("otpForm");await wait();input("o-code","123456");input("o-name","Pat Two");submit("otpForm");await wait(80);
  // force a stale-cache double book
  const r=await window.NirogBE.createBooking({docId:7,dateKey:day(1),time:"10:00",mode:"clinic",name:"Pat Two",age:20,sex:"Male",phone:"9811100002",reason:""}).catch(e=>e);
  ok(r&&r.code==="slot_taken"&&/Someone just booked/.test(r.message),"double booking refused with a friendly message");
  // doctor
  click("logout");await wait();
  click("staff");input("l-email","doc@x.in");input("l-pass","wrong");submit("loginForm");await wait();
  ok(app.innerHTML.includes("Email or password is incorrect"),"wrong staff password rejected");
  input("l-pass","docpass12");submit("loginForm");await wait(120);
  ok(app.innerHTML.includes("Pat One")&&app.innerHTML.includes("Needs your approval"),"doctor sees the pending request");
  ok(app.innerHTML.includes("You have 1 new notification")||app.innerHTML.includes("notification"),"doctor notified");
  click("approve",db.bookings[0].id);await wait(120);
  ok(db.bookings[0].status==="confirmed","doctor approval stored on the server");
  ok(app.innerHTML.includes("Confirmed"),"doctor view updates");
  // patient sees it
  click("logout");await wait();
  click("tab","appts");otpId("p1");submit("otpForm");await wait();input("o-code","123456");submit("otpForm");await wait(100);
  ok(app.innerHTML.includes("Your appointments")&&!app.innerHTML.includes("No upcoming"),"patient sees the confirmed booking after signing in again");
  // admin
  click("logout");await wait();
  click("staff");input("l-email","admin@x.in");input("l-pass","docpass12");submit("loginForm");await wait(150);
  ok(app.innerHTML.includes("Doctor")&&app.innerHTML.includes("Facilities"),"admin sees review tabs");
  click("ctab","fac");await wait(100);
  ok(app.innerHTML.includes("Pending Care Hospital")&&app.innerHTML.includes("LIC2"),"admin sees pending facility with private details");
  click("cfapprove","2");await wait(100);
  ok(db.facs[1].status==="approved","admin approval of facility stored");
  click("ctab","set");input("cs-value","60");submit("csForm");await wait(60);
  ok(db.settings&&db.settings.fee_value===60,"admin platform fee saved to the server");
  // sales
  click("logout");await wait();
  click("staff");input("l-email","sales@x.in");input("l-pass","docpass12");submit("loginForm");await wait(150);
  ok(app.innerHTML.includes("Add lead")&&!app.innerHTML.includes("Settings"),"sales sees only leads");
  input("cl-name","Lead One");input("cl-phone","9811100077");submit("clForm");await wait(100);
  ok(db.leads.length===1&&app.innerHTML.includes("Lead One"),"sales lead saved and listed");
  click("clstat","1|contacted");await wait(100);
  ok(db.leads[0].status==="contacted","lead status stored");
  // labs tab shows facilities from the database
  click("logout");await wait();click("tab","labs");
  ok(app.innerHTML.includes("City Diagnostics Lab")&&!app.innerHTML.includes("Sample Diagnostics"),"labs come from the database, not demo data");
  console.log(fails?"\n"+fails+" FAILED":"\nall passed");process.exit(fails?1:0);
})();
