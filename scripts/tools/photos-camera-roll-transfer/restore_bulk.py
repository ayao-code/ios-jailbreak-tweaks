#!/usr/bin/env python3
"""Authorized camera-roll recovery with bounded transfer/import overlap.
No credentials, no source deletion, no direct Photos database mutation.
"""
import argparse,collections,datetime,hashlib,io,json,os,pathlib,queue,shlex,sqlite3,subprocess,tarfile,threading,time,traceback
B='/var/jb/usr/bin/'
def atomic(path,value):
 p=pathlib.Path(path);tmp=p.with_suffix(p.suffix+'.new');tmp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n');tmp.chmod(0o600);tmp.replace(p)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--operation',required=True);args=ap.parse_args();root=pathlib.Path(args.operation);cfg=json.loads((root/'bulk-config.json').read_text());start=time.monotonic()
 lock=root/'bulk.lock';fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.write(fd,str(os.getpid()).encode());os.close(fd)
 ssh=['ssh','-S',cfg['target_socket'],'-o','BatchMode=yes','-o','ServerAliveInterval=15','mobile@'+cfg['target_host']]
 source=['ssh','-S',cfg['source_socket'],'-o','BatchMode=yes','-o','ServerAliveInterval=15','mobile@'+cfg['source_host']]
 def run(cmd,data=None,target=None):
  p=subprocess.run((target or ssh)+[B+'sh -c '+shlex.quote(cmd)],input=data,capture_output=True)
  if p.returncode:raise RuntimeError(f'Remote failure {p.returncode}: {p.stderr.decode(errors="replace")[:1500]}')
  return p.stdout
 def remote_json(path):
  raw=run('if [ -f '+shlex.quote(path)+' ]; then '+B+'cat '+shlex.quote(path)+'; fi')
  return json.loads(raw) if raw else None
 def snapshot(label):
  paths=['rootfs/var/mobile/Media/PhotoData/Photos.sqlite','rootfs/var/mobile/Media/PhotoData/Photos.sqlite-wal']
  for attempt in range(4):
   cmd=B+'sha256sum '+' '.join('/'+p for p in paths);h1=run(cmd);data=run(B+'tar -cf - -C / '+' '.join(paths));h2=run(cmd)
   if h1==h2:break
   time.sleep(1)
  else:raise RuntimeError('Photos DB/WAL is changing; snapshot refused')
  f=root/(label+'.tar');f.write_bytes(data)
  with tarfile.open(fileobj=io.BytesIO(data)) as t:
   for m in t:
    if m.isfile():(root/(label+'-'+pathlib.PurePosixPath(m.name).name)).write_bytes(t.extractfile(m).read())
  c=sqlite3.connect(f'file:{root}/{label}-Photos.sqlite?mode=ro',uri=True);c.row_factory=sqlite3.Row
  assert c.execute('pragma quick_check').fetchone()[0]=='ok'
  rows=[dict(a) for a in c.execute('select ZUUID,ZTRASHEDSTATE,ZBUNDLESCOPE,ZFILENAME,ZDIRECTORY,ZDATECREATED,ZADDEDDATE,ZLATITUDE,ZLONGITUDE,ZKIND,ZKINDSUBTYPE,ZHIDDEN,ZFAVORITE from ZASSET')];c.close();atomic(root/(label+'-assets.json'),rows)
  return rows,data
 def status(phase,**kw):
  atomic(root/'bulk-status.json',{'phase':phase,'pid':os.getpid(),'updated_at':datetime.datetime.now().isoformat(),'elapsed_seconds':round(time.monotonic()-start),'total_assets':len(plans),'verified_assets':len(done),'remaining_assets':len(plans)-len(done),'total_original_files':cfg['resource_count'],'source_originals_deleted':False,**kw})
 plans=json.loads((root/'bulk-plans.json').read_text());done={a['source_uuid']:a for a in cfg['sample_receipts']};stop=threading.Event();ready=queue.Queue(maxsize=1);failed=[];uploaded=0
 try:
  if (root/'completed-assets.json').exists():raise RuntimeError('Operation already started; use persisted state, do not start duplicate')
  before,raw=snapshot('bulk-before');personal=[a for a in before if a['ZTRASHEDSTATE']==0 and a['ZBUNDLESCOPE']==0];assert {a['ZUUID'] for a in personal}=={a['target_uuid'] for a in done.values()},'Current active camera roll differs from verified samples'
  run(B+'mkdir -p '+shlex.quote(cfg['logical_root']));run(B+'cat > '+shlex.quote(cfg['logical_root']+'/bulk-before.tar'),raw)
  inspect=run(shlex.quote(cfg['tool'])+' inspect').decode();assert 'addedDateSupported=1' in inspect and 'photosAuthorization=3' in inspect
  atomic(root/'completed-assets.json',list(done.values()));status('preflight_hashing')
  # Hash all local sources once; read-only check, then enforce size/mtime at transfer.
  local_resources={r['local_path']:r for p in plans if p['sourceUUID'] not in done for r in [p['primary']]+([p['pairedVideo']] if 'pairedVideo' in p else []) if r.get('local_path')};stats={}
  import concurrent.futures
  def check_local(pair):
   path,r=pair;f=pathlib.Path(path);st=f.stat();h=hashlib.sha256()
   with f.open('rb') as s:
    for b in iter(lambda:s.read(4*1024*1024),b''):h.update(b)
   now=f.stat();assert st.st_size==now.st_size==r['bytes'] and st.st_mtime_ns==now.st_mtime_ns and h.hexdigest()==r['sha256'],path
   return path,(st.st_size,st.st_mtime_ns)
  with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
   for i,(path,st) in enumerate(pool.map(check_local,local_resources.items()),1):
    stats[path]=st
    if i%1000==0:print('LOCAL HASH VERIFIED',i,'/',len(local_resources),flush=True)
  remote_resources=[r for p in plans if p['sourceUUID'] not in done for r in [p['primary']]+([p['pairedVideo']] if 'pairedVideo' in p else []) if r.get('source_device_path')]
  if remote_resources:
   hashes=run(B+'xargs -0 -r '+B+'sha256sum -z --',b'\0'.join(r['source_device_path'].encode() for r in remote_resources)+b'\0',target=source);hm={}
   for item in hashes.split(b'\0'):
    if item:h,path=item.split(b'  ',1);hm[path.decode()]=h.decode()
   for r in remote_resources:assert hm[r['source_device_path']]==r['sha256']
  pending=[p for p in plans if p['sourceUUID'] not in done];batches=[];batch=[];size=0
  for p in pending:
   n=sum(r['bytes'] for r in [p['primary']]+([p['pairedVideo']] if 'pairedVideo' in p else []))
   if batch and (len(batch)>=24 or size+n>320*1024*1024):batches.append(batch);batch=[];size=0
   batch.append(p);size+=n
  if batch:batches.append(batch)
  atomic(root/'batch-layout.json',[[p['sourceUUID'] for p in b] for b in batches]);status('running',total_batches=len(batches));print('PREFLIGHT OK: batches',len(batches),'remaining assets',len(pending),flush=True)
  def put(value):
   while not stop.is_set():
    try:ready.put(value,timeout=1);return True
    except queue.Full:continue
   return False
  def producer():
   nonlocal uploaded
   try:
    for index,items in enumerate(batches,1):
     if stop.is_set():break
     tag=f'batch-{index:04d}';ld=cfg['logical_root']+'/'+tag;pd=cfg['physical_root']+'/'+tag
     run(B+'mkdir -p '+shlex.quote(ld))
     command=B+'tar -xf - -C '+shlex.quote(ld);proc=subprocess.Popen(ssh+[command],stdin=subprocess.PIPE,stderr=subprocess.PIPE);sent=0;t0=time.monotonic();source_procs=[]
     try:
      with tarfile.open(fileobj=proc.stdin,mode='w|',bufsize=1024*1024) as tar:
       for p in items:
        if stop.is_set():raise RuntimeError('Producer stopped')
        for r in [p['primary']]+([p['pairedVideo']] if 'pairedVideo' in p else []):
         ti=tarfile.TarInfo(p['sourceUUID']+'/'+r['originalFilename']);ti.size=r['bytes'];ti.mode=0o600
         if r.get('local_path'):
          f=pathlib.Path(r['local_path']);st=f.stat();assert (st.st_size,st.st_mtime_ns)==stats[str(f)]
          with f.open('rb') as stream:tar.addfile(ti,stream)
          after=f.stat();assert (after.st_size,after.st_mtime_ns)==stats[str(f)]
         else:
          sp=subprocess.Popen(source+[B+'cat '+shlex.quote(r['source_device_path'])],stdout=subprocess.PIPE,stderr=subprocess.PIPE);source_procs.append(sp);tar.addfile(ti,sp.stdout);err=sp.stderr.read();assert sp.wait()==0,err.decode()
         sent+=r['bytes']
      proc.stdin.close();err=proc.stderr.read();rc=proc.wait();assert rc==0,err.decode()
     finally:
      if proc.poll() is None:proc.terminate();proc.wait()
      for sp in source_procs:
       if sp.poll() is None:sp.terminate();sp.wait()
     device=[]
     for p in items:
      q={k:v for k,v in p.items() if k not in ['primary','pairedVideo']}
      for key in ['primary','pairedVideo']:
       if key in p:
        r=p[key];q[key]={k:v for k,v in r.items() if k not in ['local_path','source_device_path']};q[key]['sourcePath']=pd+'/'+p['sourceUUID']+'/'+r['originalFilename']
      device.append(q)
     atomic(root/(tag+'-uploaded.json'),{'source_uuids':[p['sourceUUID'] for p in items],'bytes':sent,'seconds':time.monotonic()-t0})
     uploaded+=1;print('UPLOADED',index,'/',len(batches),'assets',len(items),'MB/s',round(sent/1e6/max(.01,time.monotonic()-t0),1),flush=True)
     if not put((index,ld,pd,device)):break
    put(None)
   except BaseException as e:failed.append(str(e));put(('ERROR',str(e)))
  thread=threading.Thread(target=producer);thread.start()
  try:
   while True:
    entry=ready.get()
    if entry is None:break
    if entry[0]=='ERROR':raise RuntimeError(entry[1])
    index,ld,pd,items=entry;tag=f'batch-{index:04d}';batch_plan={'expectedAssetCount':len(done),'items':items};atomic(root/(tag+'-plan.json'),batch_plan);run(B+'cat > '+shlex.quote(ld+'/plan.json'),json.dumps(batch_plan).encode())
    receipt=remote_json(ld+'/batch-receipt.json');verb='import-batch' if receipt is None else 'finish-batch';arg=pd+'/plan.json' if receipt is None else pd+'/batch-receipt.json'
    atomic(root/(tag+'-attempt.json'),{'command':verb,'started':datetime.datetime.now().isoformat(),'source_uuids':[p['sourceUUID'] for p in items]})
    t0=time.monotonic();result=run(shlex.quote(cfg['tool'])+' '+verb+' '+shlex.quote(arg));(root/(tag+'-import.log')).write_bytes(result)
    receipt=remote_json(ld+'/batch-receipt.json');verified=remote_json(ld+'/batch-verified.json');assert receipt and verified and verified['status']=='verified' and verified['count']==len(items)
    atomic(root/(tag+'-receipt.json'),receipt);atomic(root/(tag+'-verified.json'),verified)
    bysource={e['plan']['sourceUUID']:e for e in receipt['entries']}
    for e in verified['entries']:
     uid=e['sourceUUID'];assert uid not in done;v=e['verification'];p=bysource[uid]['plan'];assert v['primarySHA256']==p['primary']['sha256'] and abs(v['added']-p['addedDate'])<.001 and abs(v['created']-p['creationDate'])<.001
     if 'pairedVideo' in p:assert v['livePhoto'] and v['pairedVideoSHA256']==p['pairedVideo']['sha256']
     done[uid]={'source_uuid':uid,'target_uuid':v['uuid'],'source_order':p['sourceOrder'],'receipt':bysource[uid],'verification':v}
    atomic(root/'completed-assets.json',list(done.values()));status('running',verified_batches=index,total_batches=len(batches),uploaded_batches=uploaded)
    # Remove only this operation's validated temporary input resources, never library or backups.
    cleanup=[r['sourcePath'] for p in items for r in [p['primary']]+([p['pairedVideo']] if 'pairedVideo' in p else [])]
    logical_paths=[ld+'/'+str(pathlib.PurePosixPath(p).relative_to(pathlib.PurePosixPath(pd))) for p in cleanup]
    run(B+'xargs -0 -r '+B+'rm --',b'\0'.join(p.encode() for p in logical_paths)+b'\0')
    print('IMPORTED VERIFIED',len(done),'/',len(plans),'batch',index,'import_seconds',round(time.monotonic()-t0,1),flush=True)
  finally:stop.set();thread.join()
  if failed:raise RuntimeError(failed[0])
  assert len(done)==len(plans);status('final_audit')
  after,_=snapshot('bulk-after');active=[a for a in after if a['ZTRASHEDSTATE']==0 and a['ZBUNDLESCOPE']==0];byid={a['ZUUID']:a for a in active};assert len(active)==len(plans) and set(byid)=={a['target_uuid'] for a in done.values()};meta={p['sourceUUID']:p for p in plans}
  location_count=0;subtype=[]
  for uid,r in done.items():
   p=meta[uid];a=byid[r['target_uuid']];assert abs(a['ZDATECREATED']-p['creationDate'])<.001 and abs(a['ZADDEDDATE']-p['addedDate'])<.001
   if abs(p['latitude'])<=90 and abs(p['longitude'])<=180:assert abs(a['ZLATITUDE']-p['latitude'])<.000001 and abs(a['ZLONGITUDE']-p['longitude'])<.000001;location_count+=1
   if a['ZKINDSUBTYPE']!=p['kindSubtype']:subtype.append({'source_uuid':uid,'original_subtype':p['kindSubtype'],'restored_subtype':a['ZKINDSUBTYPE']})
  assert [a['ZUUID'] for a in sorted(active,key=lambda a:a['ZADDEDDATE'])]==[r['target_uuid'] for r in sorted(done.values(),key=lambda a:a['source_order'])]
  atomic(root/'final-audit.json',{'restored_assets':len(done),'original_resource_files':cfg['resource_count'],'all_original_hashes_verified':True,'all_original_dates_and_import_order_verified':True,'gps_assets_verified':location_count,'system_derived_subtype_differences':subtype,'shared_albums_restored':False,'recently_deleted_restored':False,'source_backups_modified':False,'samples_user_confirmed':True})
  status('partial_complete_deferred_sources' if cfg.get('deferred_source_assets') else 'complete',gps_assets_verified=location_count,subtype_differences=len(subtype),deferred_source_assets=cfg.get('deferred_source_assets',[]));print('RESTORE PARTIAL COMPLETE' if cfg.get('deferred_source_assets') else 'RESTORE COMPLETE',len(done),'assets',flush=True)
 except BaseException as e:
  stop.set();atomic(root/'failure.json',{'error':str(e),'traceback':traceback.format_exc(),'verified_assets':len(done),'pid':os.getpid(),'do_not_reimport_created_receipts':True});status('stopped_requires_inspection',error=str(e));raise
 finally:lock.unlink(missing_ok=True)
if __name__=='__main__':main()
