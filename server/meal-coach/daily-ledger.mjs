import {DatabaseSync} from 'node:sqlite';
import {closeSync,openSync,lstatSync} from 'node:fs';

// Only hashes, dates, counters and lease state. Never store meals or answers.
export class DailyLedger {
  constructor(path) {
    try { const fd=openSync(path,'wx',0o600);closeSync(fd); }
    catch(error) { if(error.code!=='EEXIST') throw error; }
    const info=lstatSync(path);
    if(!info.isFile() || info.isSymbolicLink() || (info.mode&0o077)!==0) throw Error('private_ledger_required');
    this.db=new DatabaseSync(path);
    this.db.exec(`PRAGMA busy_timeout=1000;
      CREATE TABLE IF NOT EXISTS days(subject TEXT NOT NULL, day TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, success TEXT, PRIMARY KEY(subject,day));
      CREATE TABLE IF NOT EXISTS requests(subject TEXT NOT NULL, day TEXT NOT NULL, id TEXT NOT NULL, fingerprint TEXT NOT NULL, status TEXT NOT NULL, lease INTEGER NOT NULL, PRIMARY KEY(subject,day,id));`);
  }
  claim(subject,day,id,fingerprint,now) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const request=this.db.prepare('SELECT * FROM requests WHERE subject=? AND day=? AND id=?').get(subject,day,id);
      let result;
      const state=this.db.prepare('SELECT * FROM days WHERE subject=? AND day=?').get(subject,day);
      const pending=this.db.prepare("SELECT lease FROM requests WHERE subject=? AND day=? AND status='pending' LIMIT 1").get(subject,day);
      if(request && request.fingerprint!==fingerprint) result='request_conflict';
      else if(state?.success) result='daily_used';
      else if(pending) result=pending.lease>now?'in_progress':'recovery_unavailable';
      else if((state?.attempts??0)>=3) result='daily_attempt_limit';
      if(result) {this.db.exec('COMMIT');return result;}
      this.db.prepare('INSERT INTO days(subject,day,attempts) VALUES(?,?,1) ON CONFLICT(subject,day) DO UPDATE SET attempts=attempts+1').run(subject,day);
      this.db.prepare("INSERT INTO requests VALUES(?,?,?,?,'pending',?) ON CONFLICT(subject,day,id) DO UPDATE SET status='pending',lease=excluded.lease").run(subject,day,id,fingerprint,now+20000);
      this.db.exec('COMMIT');return 'claimed';
    } catch(error) {this.db.exec('ROLLBACK');throw error;}
  }
  finish(subject,day,id,success,{unattempted=false}={}) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if(success) this.db.prepare('UPDATE days SET success=? WHERE subject=? AND day=?').run(id,subject,day);
      if(unattempted) this.db.prepare('UPDATE days SET attempts=MAX(0,attempts-1) WHERE subject=? AND day=?').run(subject,day);
      this.db.prepare('UPDATE requests SET status=?,lease=0 WHERE subject=? AND day=? AND id=?').run(success?'success':'failed',subject,day,id);
      this.db.exec('COMMIT');
    } catch(error) {this.db.exec('ROLLBACK');throw error;}
  }
  close() {this.db.close();}
}
