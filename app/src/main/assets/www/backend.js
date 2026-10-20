/* Yada+ backend client. Talks to Supabase over plain fetch (GoTrue + PostgREST), so no vendor library is needed.
   Only the public URL and the publishable (anon) key are used here. Row Level Security decides what each user may do.
   Exposes window.NirogBE. Inactive (BE.on === false) when config.js has no URL or key. */
(function(root){
"use strict";
var C=(root.NIROG_CONFIG||{});
var URL_=String(C.supabaseUrl||"").replace(/\/+$/,""),KEY_=String(C.supabaseAnonKey||"");
var SKEY="nirog-sb-session-v1";
var BE={on:!!(URL_&&KEY_&&/^https:\/\//.test(URL_)&&KEY_.indexOf("service_role")<0),sess:null,doctors:[],settings:null};
if(KEY_&&/^eyJ/.test(KEY_)){try{var pl=JSON.parse(atob(KEY_.split(".")[1].replace(/-/g,"+").replace(/_/g,"/")));if(pl.role==="service_role")BE.on=false}catch(e){}}

function ls(op,k,v){try{if(op==="g")return root.localStorage.getItem(k);if(op==="s")root.localStorage.setItem(k,v);else root.localStorage.removeItem(k)}catch(e){}return null}
function loadSess(){try{var s=JSON.parse(ls("g",SKEY));if(s&&s.access_token&&s.user)BE.sess=s}catch(e){}}
function saveSess(s){BE.sess=s;if(s)ls("s",SKEY,JSON.stringify({access_token:s.access_token,refresh_token:s.refresh_token,expires_at:s.expires_at,user:{id:s.user.id,email:s.user.email,phone:s.user.phone}}));else ls("r",SKEY)}
loadSess();

function friendly(code,status){
  var m={not_a_patient:"Only patient accounts can be deleted here.",invalid_whatsapp:"Enter a valid 10-digit WhatsApp number.",invalid_title:"Enter a title for the ad.",invalid_link:"The sponsor link must start with https://",too_many_images:"Use at most 8 photos.",invalid_link:"The sponsor link must start with https://",too_many_images:"Use at most 8 photos.",invalid_media:"Choose a photo or a video.",invalid_dates:"The end date cannot be before the start date.",mobile_required:"Enter your 10-digit mobile number.",invalid_category:"Choose an expense type.",invalid_amount:"Enter a whole rupee amount above zero.",program_off:"The referral programme is paused right now.",invalid_link:"Enter a link that starts with https:// (Google Meet, Zoom, Jitsi) or a 10-digit WhatsApp number.",not_video:"This is not a video consultation.",invalid_code:"That code was not found.",own_code:"You cannot use your own code.",already_applied:"A code was already added to this account.",too_late:"A code can only be added within 3 days of signing up.",invalid_upi:"Enter a valid UPI id, like name@bank.",below_minimum:"The amount is below the minimum withdrawal.",insufficient_balance:"The amount is more than your wallet balance.",pending_exists:"You already have a withdrawal waiting for payment.",not_allowed:"Staff accounts cannot use referral codes.",utr_required:"Enter the UTR / reference number of the payment.",already_decided:"This request was already handled.",slot_taken:"Someone just booked that time. Please pick another slot.",slot_unavailable:"That time is not available any more.",doctor_unavailable:"This doctor is not taking bookings right now.",
    not_authenticated:"Please sign in again.",patients_only:"Only patient accounts can book appointments.",too_many_active_bookings:"You have too many active bookings. Cancel one first.",
    not_pending:"This request was already handled.",not_cancellable:"This appointment can no longer be cancelled.",booking_not_found:"Appointment not found.",admins_only:"Only admins can do this.",
    doctors_only:"Only doctors can do this.",visit_not_done:"You can rate a visit after the appointment time has passed.",booking_not_confirmed:"Only confirmed visits can be rated.",call_not_open:"The video call opens at the slot time.",call_closed:"The video call window for this visit has ended.",invalid_rating:"Choose 1 to 5 stars.",comment_too_long:"Keep the review under 500 characters.",booking_not_found:"That appointment was not found.",has_bookings:"This doctor has bookings, so the profile cannot be deleted. Reject it instead.",not_found:"That profile was not found. It may already be deleted.",phone_in_use:"This mobile number is already registered with Yada+. Use a different number, or sign in with the account that has it.",already_registered:"This account is already registered as a doctor, facility or staff member.",account_has_bookings:"This account already has bookings, so it cannot become a doctor or facility. Use a different number or email.",
    facility_unavailable:"This listing cannot take requests right now.",invalid_item:"Choose or type the test or service you need.",invalid_name:"Enter your name.",invalid_phone:"Enter a 10-digit mobile number.",invalid_date:"Choose a date from today up to 60 days ahead.",too_many_requests:"You already have 5 open requests. Wait for a reply or cancel one.",already_decided:"This request was already answered.",upload_denied:"Upload was refused. Sign in as super admin again and retry.",user_already_exists:"That email already has an account.",email_exists:"That email already has an account.",confirm_email:"Check your email to confirm your address, then register again.",invalid_credentials:"Email or password is incorrect.",invalid_otp:"That code is not right or has expired.",rate_limited:"Too many codes requested. Wait a few minutes and try again.",sms_failed:"The SMS could not be sent. Try again in a minute.",sms_not_configured:"SMS sign-in is not switched on yet.",otp_expired:"That code has expired. Send a new one.",over_sms_send_rate_limit:"Too many codes requested. Wait a minute and try again.",upload_failed:"A file could not be uploaded. Try a smaller file.",over_email_send_rate_limit:"Too many emails were sent just now. Wait an hour and try again, or ask the Yada+ team to set up email sending.",weak_password:"Choose a stronger password (at least 8 characters, not a common one).",signup_disabled:"New sign-ups are switched off right now.",email_address_invalid:"That email address is not accepted.",oauth_failed:"Google sign-in did not complete. Please try again.",invalid_name:"Enter a valid name.",invalid_phone:"Enter a valid 10-digit mobile number.",invalid_age:"Enter a valid age.",invalid_sex:"Choose a sex.",invalid_mode:"Choose clinic or video.",invalid_days:"Choose at least one working day.",invalid_sessions:"Add one to three sessions.",invalid_title:"Enter a title (up to 80 characters).",invalid_city:"The city name is too long.",invalid_message:"The message can be up to 500 characters.",invalid_audience:"Choose who should get it.",invalid_media:"The photo or video was not accepted. Try another file.",doctors_only:"Only the treating doctor can do this.",visit_not_started:"You can write the prescription from the day of the visit.",empty_prescription:"Add at least one medicine, some advice, or a photo.",invalid_files:"A prescription file was not accepted. Try again.",too_many_files:"You can attach up to 4 photos.",too_many_medicines:"A prescription can list up to 15 medicines.",invalid_follow_up:"Choose a follow-up date that is today or later."};
  if(m[code])return m[code];
  if(status===0)return "You look offline. Check your connection and try again.";
  if(status===401||status===403)return "Please sign in again.";
  if(status===429)return "Too many attempts. Wait a minute and try again.";
  return "Something went wrong"+(code?" ("+code+")":"")+". Please try again.";
}
function BEErr(code,status,raw){var e=new Error(friendly(code,status));e.code=code;e.status=status;e.raw=raw;return e}

function rawFetch(path,opt,tok){
  opt=opt||{};
  var h={"apikey":KEY_,"Content-Type":"application/json"};
  h.Authorization="Bearer "+(tok||KEY_);
  if(opt.prefer)h.Prefer=opt.prefer;
  var f=root.fetch;
  if(!f)return Promise.reject(BEErr("offline",0));
  return f(URL_+path,{method:opt.method||"GET",headers:h,body:opt.body===undefined?undefined:JSON.stringify(opt.body)}).then(function(r){
    return r.text().then(function(t){
      var j=null;try{j=t?JSON.parse(t):null}catch(e){}
      if(!r.ok){
        var msg=j&&(j.message||j.msg||j.error_description||j.error)||"";
        var code=String(msg);
        var m=/^[a-z_]+$/.exec(code);
        throw BEErr(m?code:(j&&j.error_code)||"http_"+r.status,r.status,j);
      }
      return j;
    });
  },function(){throw BEErr("offline",0)});
}
function token(){
  var s=BE.sess;if(!s)return Promise.resolve(null);
  var now=Math.floor(Date.now()/1000);
  if(s.expires_at&&s.expires_at-now>30)return Promise.resolve(s.access_token);
  return rawFetch("/auth/v1/token?grant_type=refresh_token",{method:"POST",body:{refresh_token:s.refresh_token}}).then(function(j){saveSess(j);return j.access_token},function(e){if(e.status===400||e.status===401){saveSess(null)}throw e});
}
function api(path,opt){return token().then(function(t){return rawFetch(path,opt,t)})}
function rpc(name,args){return api("/rest/v1/rpc/"+name,{method:"POST",body:args||{}})}
function sel(table,qs){return api("/rest/v1/"+table+(qs?"?"+qs:""))}
BE.registerPush=function(t){return rpc("register_push_token",{p_token:t})};
BE.deleteMyFiles=function(){
  var uid=BE.userId();if(!uid)return Promise.resolve();
  return Promise.all(["doctor-media","verification-docs"].map(function(bk){
    return api("/storage/v1/object/list/"+bk,{method:"POST",body:{prefix:uid,limit:200}}).then(function(l){
      var names=(l||[]).filter(function(o){return o&&o.name&&o.id}).map(function(o){return uid+"/"+o.name});
      if(!names.length)return;
      return api("/storage/v1/object/"+bk,{method:"DELETE",body:{prefixes:names}});
    }).catch(function(){});
  }));
};
BE.deleteAccount=function(){return BE.deleteMyFiles().then(function(){return rpc("delete_my_account",{})})};
BE.dropPush=function(t){return rpc("drop_push_token",{p_token:t})};
BE.pushBroadcast=function(id){return token().then(function(t){return rawFetch("/functions/v1/send-push",{method:"POST",body:{broadcast_id:id}},t)})};
BE.rpc=rpc;BE.sel=sel;BE.friendly=friendly;

/* ---------- auth ---------- */
BE.signedIn=function(){return !!BE.sess};
BE.userId=function(){return BE.sess?BE.sess.user.id:null};
/* id is an email address or a 10-digit Indian mobile number */
function isMail(id){return String(id).indexOf("@")>-1}
function smsFn(body){return fetch(URL_+"/functions/v1/sms-otp",{method:"POST",headers:{"content-type":"application/json",apikey:KEY_,authorization:"Bearer "+KEY_},body:JSON.stringify(body)}).then(function(r){return r.text().then(function(t){try{return JSON.parse(t)}catch(e){return {}}}).then(function(j){if(!r.ok)throw BEErr(j.error||"sms_failed",r.status);return j})},function(){throw BEErr("network",0)})}
BE.sendOtp=function(id){if(!isMail(id))return smsFn({action:"send",mobile:id}).then(function(){return true});return rawFetch("/auth/v1/otp",{method:"POST",body:{email:id,create_user:true}}).then(function(){return true})};
BE.verifyOtp=function(id,code){if(!isMail(id))return smsFn({action:"verify",mobile:id,code:code}).then(function(j){if(!j||!j.access_token)throw BEErr("invalid_otp",400);saveSess(j);return j});return rawFetch("/auth/v1/verify",{method:"POST",body:{type:"email",email:id,token:code}}).then(function(j){if(!j||!j.access_token)throw BEErr("invalid_otp",400);saveSess(j);return j})};
/* Google sign-in: the app opens the browser at this URL; Supabase returns to redirectTo with the session in the URL fragment. */
BE.googleUrl=function(redirectTo){return URL_+"/auth/v1/authorize?provider=google&redirect_to="+encodeURIComponent(redirectTo)};
BE.finishOAuth=function(frag){
  var q={};String(frag||"").replace(/^[#?]/,"").split("&").forEach(function(kv){var i=kv.indexOf("=");if(i>0)q[decodeURIComponent(kv.slice(0,i))]=decodeURIComponent(kv.slice(i+1).replace(/\+/g," "))});
  if(q.error||q.error_description)return Promise.reject(BEErr("oauth_failed",400));
  if(!q.access_token)return Promise.reject(BEErr("oauth_failed",400));
  return rawFetch("/auth/v1/user",{},q.access_token).then(function(u){
    saveSess({access_token:q.access_token,refresh_token:q.refresh_token||"",expires_at:q.expires_at?+q.expires_at:Math.floor(Date.now()/1000)+(+q.expires_in||3600),user:{id:u.id,email:u.email,phone:u.phone}});
    var m=u.user_metadata||{};return {name:String(m.full_name||m.name||"").slice(0,80)};
  });
};
BE.signInPassword=function(email,pw){return rawFetch("/auth/v1/token?grant_type=password",{method:"POST",body:{email:email,password:pw}}).then(function(j){saveSess(j);return j})};
BE.signUpPassword=function(email,pw){return rawFetch("/auth/v1/signup",{method:"POST",body:{email:email,password:pw}}).then(function(j){if(j&&j.access_token){saveSess(j);return j}throw BEErr("confirm_email",400)})};
BE.signOut=function(){var t=BE.sess&&BE.sess.access_token;saveSess(null);if(t)return rawFetch("/auth/v1/logout",{method:"POST"},t).catch(function(){});return Promise.resolve()};
BE.me=function(){
  var id=BE.userId();if(!id)return Promise.resolve(null);
  return sel("profiles","id=eq."+id+"&select=id,role,full_name,phone,email").then(function(r){return r&&r[0]||null});
};
BE.setName=function(name){var id=BE.userId();return api("/rest/v1/profiles?id=eq."+id,{method:"PATCH",body:{full_name:name}})};

/* ---------- directory ---------- */
function hm(t){return String(t).slice(0,5)}
function mins(t){var p=String(t).split(":");return +p[0]*60+ +p[1]}
function mapDocs(docs,locs,avs){
  var loc={},av={};
  locs.forEach(function(l){if(!loc[l.doctor_id])loc[l.doctor_id]=l});
  avs.forEach(function(a){(av[a.doctor_id]=av[a.doctor_id]||[]).push(a)});
  return docs.map(function(d){
    var l=loc[d.id]||{},a=av[d.id]||[],days=[],hours=[],step=20;
    a.forEach(function(x){if(days.indexOf(x.weekday)<0)days.push(x.weekday);var b=[x.start_min,x.end_min];if(!hours.some(function(h){return h[0]===b[0]&&h[1]===b[1]}))hours.push(b);step=x.step_min});
    days.sort();
    return {id:d.id,name:d.name,spec:d.spec,exp:d.exp_years,qual:d.qual,fee:d.fee_inr,vfee:d.video_fee_inr,video:!!d.video,rating:0,reviews:0,lang:d.languages,
      clinic:d.clinic||l.name||"",city:d.city,address:l.address||"",pin:l.pin||"",mapUrl:l.map_url||"",lat:l.lat,lng:l.lng,about:d.about,days:days,hours:hours,step:step,off:[],blocked:[],
      status:d.status||"approved",reason:d.review_reason||"",ref:d.ref||"",registered:true,managed:true,verified:!!d.verified,photo:d.photo_path?URL_+"/storage/v1/object/public/doctor-media/"+d.photo_path:"",photoPath:d.photo_path||"",wa:d.wa||"",cloud:true};
  });
}
var DCOLS="id,name,spec,qual,exp_years,fee_inr,video_fee_inr,video,languages,about,clinic,city,photo_path,wa,status,verified,review_reason,ref";
BE.loadDirectory=function(){
  return Promise.all([
    sel("doctors","select="+DCOLS+"&status=eq.approved&order=id"),
    sel("clinic_locations","select=id,doctor_id,name,address,city,pin,map_url,lat,lng"),
    sel("doctor_availability","select=doctor_id,weekday,start_min,end_min,step_min&order=start_min"),
    sel("platform_settings","select=*"),
    sel("doctor_ratings","select=doctor_id,avg_rating,n").catch(function(){return []})
  ]).then(function(r){
    BE.settings=r[3]&&r[3][0]||null;
    BE.doctors=mapDocs(r[0],r[1],r[2]);
    (r[4]||[]).forEach(function(x){BE.doctors.forEach(function(d){if(d.id===x.doctor_id){d.rating=+x.avg_rating;d.reviews=x.n}})});
    return BE.doctors;
  });
};
/* The signed-in doctor's own record, whatever its review status, with their day-offs and blocked slots. */
BE.loadMine=function(id){
  return Promise.all([
    sel("doctors","select="+DCOLS+"&id=eq."+id),
    sel("clinic_locations","select=id,doctor_id,name,address,city,pin,map_url,lat,lng&doctor_id=eq."+id),
    sel("doctor_availability","select=doctor_id,weekday,start_min,end_min,step_min&doctor_id=eq."+id+"&order=start_min"),
    sel("doctor_exceptions","select=day,slot_time&doctor_id=eq."+id)
  ]).then(function(r){
    var d=mapDocs(r[0],r[1],r[2])[0];if(!d)return null;
    r[3].forEach(function(x){if(x.slot_time==null)d.off.push(x.day);else d.blocked.push(x.day+"|"+hm(x.slot_time))});
    return d;
  });
};
/* Admin: everything pending review plus the registration details. */
BE.adminDoctors=function(){
  return Promise.all([
    sel("doctors","select="+DCOLS+"&order=id.desc&limit=200"),
    sel("doctor_verification","select=doctor_id,council,reg_no,reg_year"),
    sel("doctor_documents","select=doctor_id,kind,storage_path,file_name")
  ]).then(function(r){
    return r[0].map(function(d){
      d.ver=r[1].filter(function(v){return v.doctor_id===d.id})[0]||null;
      d.docs=r[2].filter(function(x){return x.doctor_id===d.id});return d;
    });
  });
};
BE.reviewDoctor=function(id,decision,reason){return rpc("admin_review_doctor",{p_doctor:id,p_decision:decision,p_verified:decision==="approve",p_reason:reason||null})};
BE.signedUrl=function(bucket,path){
  return api("/storage/v1/object/sign/"+bucket+"/"+path,{method:"POST",body:{expiresIn:300}}).then(function(j){return URL_+"/storage/v1"+j.signedURL});
};
BE.setPhone=function(phone10){var id=BE.userId();return api("/rest/v1/profiles?id=eq."+id,{method:"PATCH",body:{phone:"+91"+phone10}}).catch(function(){})};
/* Slots for one doctor and day, straight from the database. Returns [{t:"09:00",st:"free"|"busy"|"past"|"blocked"}]. */
BE.openSlots=function(docId,dateKey){
  return rpc("open_slots",{p_doctor:docId,p_day:dateKey}).then(function(rows){
    return (rows||[]).map(function(r){var s=r.state;return {t:hm(r.slot_time),st:s==="free"?"free":s==="booked"||s==="busy"?"busy":s==="past"?"past":s==="blocked"?"blocked":"busy"}});
  });
};

/* ---------- bookings ---------- */
var ST={pending:"pending",confirmed:"upcoming",rejected:"rejected",cancelled:"cancelled",completed:"upcoming"};
function toAppt(b){
  return {id:b.id,ref:b.ref,docId:b.doctor_id,dateKey:b.slot_date,time:hm(b.slot_time),mode:b.mode,age:b.patient_age,sex:b.patient_sex,fee:b.doctor_fee,pf:b.platform_fee,
    name:b.patient_name,phone:b.patient_phone,reason:b.reason||"",status:ST[b.status]||b.status,rreason:b.decision_reason||"",retimed:!!b.retimed,link:b.call_link||"",callAt:b.call_started_at?Date.parse(b.call_started_at):0,cloud:true};
}
BE.toAppt=toAppt;
BE.myBookings=function(){return sel("bookings","select=*&order=slot_date.desc,slot_time.desc&limit=200").then(function(r){return (r||[]).map(toAppt)})};
BE.createBooking=function(o){
  return rpc("create_booking",{p_doctor:o.docId,p_day:o.dateKey,p_time:o.time,p_mode:o.mode,p_name:o.name,p_age:o.age,p_sex:o.sex,p_phone:o.phone,p_reason:o.reason||""}).then(toAppt);
};
BE.decide=function(id,decision,time,reason){return rpc("doctor_decide_booking",{p_booking:id,p_decision:decision,p_time:time||null,p_reason:reason||null}).then(toAppt)};
BE.setCallLink=function(id,link){return rpc("set_call_link",{p_booking:id,p_link:link||null})};
BE.startCall=function(id){return rpc("start_call",{p_booking:id})};
BE.endCall=function(id){return rpc("end_call",{p_booking:id})};
BE.cancel=function(id){return rpc("cancel_booking",{p_booking:id}).then(toAppt)};
BE.reschedule=function(id,dateKey,time){return rpc("reschedule_booking",{p_booking:id,p_day:dateKey,p_time:time}).then(toAppt)};

/* ---------- notifications ---------- */
BE.notifications=function(){return sel("notifications","select=id,body,created_at,read_at,broadcast_id&order=created_at.desc&limit=100")};
BE.markRead=function(){return rpc("mark_notifications_read")};

/* ---------- doctor self-service ---------- */
BE.adminProfile=function(kind,id){return rpc("admin_profile",{p_kind:kind,p_id:id})};
BE.adminDelete=function(kind,id){return kind==="fac"?rpc("admin_delete_facility",{p_facility:id}):rpc("admin_delete_doctor",{p_doctor:id})};
BE.adminUpdate=function(kind,id,p){return kind==="fac"?rpc("admin_update_facility",{p_facility:id,p:p}):rpc("admin_update_doctor",{p_doctor:id,p:p})};
BE.loadReviews=function(docId){return sel("doctor_reviews","select=id,rating,comment,patient_name,created_at&doctor_id=eq."+docId+"&order=created_at.desc&limit=50").catch(function(){return []})};
BE.myReviews=function(){return sel("reviews","select=booking_id,rating,comment").catch(function(){return []})};
BE.submitReview=function(bookingId,rating,comment){return rpc("submit_review",{p_booking:bookingId,p_rating:rating,p_comment:comment||""})};
BE.myRx=function(){return sel("prescriptions","select=*&order=updated_at.desc&limit=200").catch(function(){return []})};
BE.saveRx=function(p){return rpc("save_prescription",{p:p})};
BE.broadcasts=function(){return sel("broadcasts","select=*&order=id.desc&limit=30").catch(function(){return []})};
BE.reach=function(aud,city){return rpc("admin_broadcast_reach",{p_audience:aud,p_city:city||null})};
BE.setCity=function(city){var id=BE.userId();if(!id)return Promise.resolve();return api("/rest/v1/patients?id=eq."+id,{method:"PATCH",body:{city:city||null}}).catch(function(){})};
BE.sendBroadcast=function(p){return rpc("admin_send_broadcast",{p:p})};
BE.deleteBroadcast=function(id){return rpc("admin_delete_broadcast",{p_id:id})};
BE.revokeBroadcast=function(id){return rpc("admin_revoke_broadcast",{p_id:id})};
BE.myReferral=function(){return rpc("my_referral",{})};
BE.applyReferral=function(c){return rpc("apply_referral",{p_code:c})};
BE.requestWithdrawal=function(a,u,m){return rpc("request_withdrawal",{p_amount:a,p_upi:u,p_mobile:m})};
BE.adminWithdrawals=function(s){return rpc("admin_withdrawals",{p_status:s||"pending"})};
BE.decideWithdrawal=function(id,d,utr,note){return rpc("admin_decide_withdrawal",{p_id:id,p_decision:d,p_utr:utr||null,p_note:note||null})};
BE.referralSettings=function(p){return rpc("admin_referral_settings",{p:p||null})};
BE.adminAccounts=function(){return rpc("admin_accounts",{})};
BE.addExpense=function(p){return rpc("admin_expense_add",{p:p})};
BE.deleteExpense=function(id){return rpc("admin_expense_delete",{p_id:id})};
BE.doctorStats=function(id){return rpc("admin_doctor_stats",{p_doctor:id})};
BE.adminPatients=function(q,off){return rpc("admin_patients",{p_search:q||"",p_limit:50,p_offset:off||0})};
BE.adminDeletePatient=function(id){return rpc("admin_delete_patient",{p_user:id})};
BE.createFacRequest=function(fid,item,date,name,phone,note){return rpc("create_facility_request",{p_facility:fid,p_item:item,p_date:date,p_name:name,p_phone:phone,p_note:note||""})};
BE.decideFacRequest=function(id,status,reason){return rpc("decide_facility_request",{p_id:id,p_status:status,p_reason:reason||""})};
BE.cancelFacRequest=function(id){return rpc("cancel_facility_request",{p_id:id})};
BE.myFacRequests=function(){return sel("facility_requests","select=*,facilities(name,kind)&order=created_at.desc&limit=100").catch(function(){return []})};
BE.requestStats=function(){return rpc("admin_request_stats",{})};
BE.setMyMobile=function(m){return rpc("set_my_mobile",{p_mobile:m})};
BE.logTap=function(kind,id,ch){return rpc("log_contact_tap",{p_kind:kind,p_target:id,p_channel:ch})};
BE.contactStats=function(kind){return rpc("admin_contact_stats",{p_kind:kind})};
BE.activeAds=function(city){return rpc("active_ads",{p_city:city||null})};
BE.logAdView=function(id){return rpc("log_ad_view",{p_id:id})};
BE.adminAds=function(){return sel("ads","select=*&order=created_at.desc&limit=100")};
BE.logAdClick=function(id){return rpc("log_ad_click",{p_id:id})};
BE.logAdClick=function(id){return rpc("log_ad_click",{p_id:id})};
BE.saveAd=function(p){return rpc("admin_save_ad",{p:p})};
BE.deleteAd=function(id){return rpc("admin_delete_ad",{p_id:id})};
BE.dashCounts=function(){return rpc("admin_dashboard_counts",{})};
BE.ambulances=function(){return sel("ambulance_services","select=*&order=kind.asc,name.asc&limit=300")};
BE.saveAmbulance=function(p){return rpc("admin_save_ambulance",{p:p})};
BE.deleteAmbulance=function(id){return rpc("admin_delete_ambulance",{p_id:id})};
BE.mediaUrl=function(path){return URL_+"/storage/v1/object/public/broadcast-media/"+path};
BE.uploadFile=function(bucket,path,file){
  return token().then(function(t){
    return root.fetch(URL_+"/storage/v1/object/"+bucket+"/"+path,{method:"POST",headers:{apikey:KEY_,Authorization:"Bearer "+t,"Content-Type":file.type||"application/octet-stream","x-upsert":(bucket==="broadcast-media"?"false":"true")},body:file}).then(function(r){if(!r.ok)throw BEErr(r.status===403||r.status===401?"upload_denied":"upload_failed",r.status);return path},function(){throw BEErr("offline",0)});
  });
};
BE.deleteReview=function(id){return rpc("admin_delete_review",{p_review:id})};
BE.registerDoctor=function(p){return rpc("register_doctor",{p:p})};
function dataBlob(u){var m=/^data:([^;]+);base64,(.*)$/.exec(u||"");if(!m)return null;var b=atob(m[2]),a=new Uint8Array(b.length);for(var i=0;i<b.length;i++)a[i]=b.charCodeAt(i);return new Blob([a],{type:m[1]})}
BE.upload=function(bucket,path,dataUrl){
  var blob=dataBlob(dataUrl);if(!blob)return Promise.reject(BEErr("invalid_file",400));
  return token().then(function(t){
    return root.fetch(URL_+"/storage/v1/object/"+bucket+"/"+path,{method:"POST",headers:{apikey:KEY_,Authorization:"Bearer "+t,"Content-Type":blob.type,"x-upsert":(bucket==="broadcast-media"?"false":"true")},body:blob}).then(function(r){if(!r.ok)throw BEErr(r.status===403||r.status===401?"upload_denied":"upload_failed",r.status);return path},function(){throw BEErr("offline",0)});
  });
};
BE.addDocRow=function(docId,kind,path,name){return api("/rest/v1/doctor_documents",{method:"POST",body:{doctor_id:docId,kind:kind,storage_path:path,file_name:name||""}})};
BE.setDoctorPhoto=function(docId,path){return api("/rest/v1/doctors?id=eq."+docId,{method:"PATCH",body:{photo_path:path}})};
BE.loadFacilities=function(){return sel("facilities","select=id,kind,sub,name,city,address,pin,map_url,hours,beds,emergency,ambulance,home_service,services,wa,status,verified,review_reason,ref&status=eq.approved&order=id")};
BE.adminFacilities=function(){return Promise.all([sel("facilities","select=id,kind,sub,name,city,address,pin,map_url,hours,wa,status,verified,review_reason,ref&order=id.desc&limit=200"),sel("facility_private","select=facility_id,contact_name,contact_phone,licence_no"),sel("facility_documents","select=facility_id,kind,storage_path")]).then(function(r){return r[0].map(function(f){f.priv=r[1].filter(function(p){return p.facility_id===f.id})[0]||null;f.docs=r[2].filter(function(x){return x.facility_id===f.id});return f})})};
BE.reviewFacility=function(id,decision,reason){return rpc("admin_review_facility",{p_facility:id,p_decision:decision,p_verified:decision==="approve",p_reason:reason||null})};
BE.myFacility=function(){return rpc("my_facility_id")};
BE.addFacDoc=function(fid,kind,path){return api("/rest/v1/facility_documents",{method:"POST",body:{facility_id:fid,kind:kind,storage_path:path,file_name:""}})};
BE.addLead=function(o){return api("/rest/v1/leads",{method:"POST",body:o})};
BE.setLeadStatus=function(id,st){return api("/rest/v1/leads?id=eq."+id,{method:"PATCH",body:{status:st}})};
BE.saveSettings=function(o){return api("/rest/v1/platform_settings?id=eq.1",{method:"PATCH",body:o})};
BE.registerFacility=function(p){return rpc("register_facility",{p:p})};
BE.myDoctor=function(){return rpc("my_doctor_id")};
BE.saveSchedule=function(docId,days,sessions,step,offDays,blocked){
  /* replace weekly sessions and exceptions for this doctor */
  var rows=[];days.forEach(function(d){sessions.forEach(function(s){rows.push({doctor_id:docId,weekday:d,start_min:s[0],end_min:s[1],step_min:step})})});
  var exc=[];(offDays||[]).forEach(function(k){exc.push({doctor_id:docId,day:k,slot_time:null})});
  (blocked||[]).forEach(function(b){var p=b.split("|");exc.push({doctor_id:docId,day:p[0],slot_time:p[1]})});
  return api("/rest/v1/doctor_availability?doctor_id=eq."+docId,{method:"DELETE"}).then(function(){
    return rows.length?api("/rest/v1/doctor_availability",{method:"POST",body:rows}):null;
  }).then(function(){return api("/rest/v1/doctor_exceptions?doctor_id=eq."+docId,{method:"DELETE"})}).then(function(){
    return exc.length?api("/rest/v1/doctor_exceptions",{method:"POST",body:exc}):null;
  });
};
BE.loadExceptions=function(docId){return sel("doctor_exceptions","select=day,slot_time&doctor_id=eq."+docId)};

root.NirogBE=BE;
})(typeof window!=="undefined"?window:globalThis);
