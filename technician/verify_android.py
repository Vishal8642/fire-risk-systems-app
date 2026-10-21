import base64
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.request
import websocket

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'device-checks'
OUT.mkdir(exist_ok=True)
PACKAGE='za.co.firerisk.technician.demo'
def adb(*args,check=True):
    return subprocess.run(['adb',*args],text=True,capture_output=True,check=check).stdout.strip()

class DevTools:
    def __init__(self,url):
        self.ws=websocket.create_connection(url,timeout=25,suppress_origin=True)
        self.counter=0
    def call(self,method,params=None):
        self.counter+=1
        self.ws.send(json.dumps({'id':self.counter,'method':method,'params':params or {}}))
        while True:
            msg=json.loads(self.ws.recv())
            if msg.get('id')!=self.counter:continue
            if 'error' in msg:raise RuntimeError(msg['error'])
            return msg.get('result',{})
    def js(self,expression):
        result=self.call('Runtime.evaluate',{'expression':expression,'returnByValue':True,'awaitPromise':True,'userGesture':True})
        if result.get('exceptionDetails'):raise RuntimeError(result['exceptionDetails'])
        return result.get('result',{}).get('value')
    def screenshot(self,name):
        result=self.call('Page.captureScreenshot',{'format':'png'})
        (OUT/name).write_bytes(base64.b64decode(result['data']))

try:
    print(adb('install','-r',str(ROOT/'Fire_Risk_Systems_Technician_Demo.apk')))
    adb('shell','pm','grant',PACKAGE,'android.permission.CAMERA')
    adb('shell','am','start','-W','-n',PACKAGE+'/.MainActivity')
    wsurl=None
    for attempt in range(35):
        entries=adb('shell','cat','/proc/net/unix')
        match=re.search(r'@?(webview_devtools_remote_\d+)',entries)
        if match:
            adb('forward','tcp:9222','localabstract:'+match.group(1))
            try:
                with urllib.request.urlopen('http://localhost:9222/json',timeout=3) as response:targets=json.load(response)
                target=next((t for t in targets if 'frs-technician.local' in t.get('url','')),None)
                if target and target.get('webSocketDebuggerUrl'):
                    wsurl=target['webSocketDebuggerUrl'];break
            except Exception:pass
        time.sleep(1)
    assert wsurl,'Embedded WebView debugging target did not become ready.'
    dev=DevTools(wsurl)
    for attempt in range(30):
        if dev.js("document.body.innerText.includes('Enter workspace')"):break
        time.sleep(1)
    assert dev.js("document.body.innerText.includes('Enter workspace')"),'Login page failed to load.'
    assert dev.js("document.body.innerText.includes('Field technician')")
    assert not dev.js("document.body.innerText.includes('Management team')")
    dev.screenshot('01-technician-login.png')
    def click(action,extra=''):
        selector='[data-action="'+action+'"]'+extra
        assert dev.js('!!document.querySelector('+json.dumps(selector)+')'),'Missing button '+selector
        dev.js('document.querySelector('+json.dumps(selector)+').click();true')
        time.sleep(.25)
    click('login')
    assert dev.js("document.body.innerText.includes('Good day, Sipho')")
    assert dev.js("session.role==='Technician'")
    assert dev.js("getComputedStyle(document.querySelector('.topbar')).display==='none'")
    assert dev.js("document.documentElement.scrollWidth<=window.innerWidth+1"),'Home screen overflows horizontally.'
    dev.screenshot('02-technician-home.png')
    click('scanner')
    click('scan-sample','[data-id="FRS-0001"]')
    click('start-inspection','[data-id="FRS-0001"]')
    click('inspection-next')
    assert dev.js('inspectionStep===1'),'Required checklist answers were not enforced.'
    dev.js("inspection.questions.filter(q=>q.type==='result').forEach((q,i)=>{document.querySelector('[data-action=\"answer\"][data-id=\"'+q.id+'\"][data-value=\"'+(i===1?'Fail':'Pass')+'\"]').click();});true")
    click('save-draft')
    assert dev.js('db.drafts.length===1')
    dev.screenshot('03-inspection-checklist.png')
    click('inspection-next')
    click('sample-photo')
    dev.screenshot('04-inspection-evidence.png')
    click('inspection-next')
    click('demo-signature')
    dev.js("document.getElementById('inspection-confirm').click();true")
    dev.screenshot('05-signature-and-review.png')
    click('inspection-next')
    assert dev.js("inspection===null&&db.inspections[0].result==='Attention required'")
    assert dev.js('db.defects[0].inspectionId===db.inspections[0].id')
    dev.screenshot('06-inspection-complete.png')
    click('pdf')
    for attempt in range(20):
        files=adb('shell','ls','/sdcard/Download/FireRiskSystems',check=False)
        if '.pdf' in files:break
        time.sleep(.5)
    assert '.pdf' in files,'Native PDF download was not saved.'
    filename=next(x for x in files.splitlines() if x.endswith('.pdf'))
    adb('pull','/sdcard/Download/FireRiskSystems/'+filename,str(OUT/'generated-service-report.pdf'))
    click('report')
    assert dev.js("document.querySelector('.report-preview').innerText.includes('Sipho Dlamini')")
    dev.screenshot('07-service-report.png')
    click('close')
    click('after-success')
    click('tech-screen','[data-id="actions"]')
    dev.screenshot('08-corrective-actions.png')
    assert dev.js("document.documentElement.scrollWidth<=window.innerWidth+1")
    assert dev.js("window.isSecureContext&&typeof navigator.mediaDevices.getUserMedia==='function'"),'Camera API is unavailable on app origin.'
    summary={'installed':True,'launched':True,'technicianOnly':True,'requiredFields':True,'draftSaved':True,'photoAndSignature':True,'submitted':True,'linkedCorrectiveAction':True,'pdfSavedToDownloads':True,'secureCameraApiPresent':True,'physicalCamera':'Requires real-device check'}
    (OUT/'verification.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary))
finally:
    (OUT/'logcat.txt').write_text(adb('logcat','-d','-t','1800',check=False))
    screenshot=subprocess.run(['adb','exec-out','screencap','-p'],capture_output=True)
    if screenshot.returncode==0:(OUT/'device-screen.png').write_bytes(screenshot.stdout)
