import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrebox_technician/api.dart';
import 'package:fyrebox_technician/main.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();final storage=<String,String>{};
 setUp((){storage.clear();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(Native.ch,(c)async{if(c.method=='putSession')storage['getSession']=c.arguments;if(c.method=='writeWorkspace')storage['readWorkspace']=c.arguments;return storage[c.method];});});
 test('twenty demo checklists, QR, persistent draft, signed inspection and PDF',()async{
  final api=AppApi();await api.loginDemo();final templates=await api.call('checklists') as List;expect(templates.length,20);expect(templates.map((t)=>t['category']).toSet().length,6);
  final sites=await api.call('sites') as List;final a=await api.call('assets','POST',{'siteId':sites.first['id'],'name':'QA extinguisher','category':'Extinguishers','serialNumber':'QA-001','position':'Reception'});
  expect((await api.call('assets/resolve?q='+a['qr_token']))['id'],a['id']);final t=templates.firstWhere((t)=>t['category']==a['category']);final r=await api.call('inspections','POST',{'assetId':a['id'],'templateId':t['id']});final p='inspections/'+r['id'];await expectLater(api.call(p+'/submit','POST',{'confirmed':true}),throwsException);
  final answers=<String,dynamic>{};for(final q in r['checklist']['questions']){answers[q['key']]=q['type']=='pass_fail'?'Pass':'Recorded';}answers[r['checklist']['questions'][0]['key']]='Fail';
  final photo=await api.upload(await File('test/fixtures/photo.jpg').readAsBytes(),a['site_id'],'photo',inspectionId:r['id']);final sig=await api.upload(await File('test/fixtures/signature.png').readAsBytes(),a['site_id'],'signature',inspectionId:r['id']);
  final b={'answers':answers,'notes':'Replace seal','serviceType':'Maintenance','workPerformed':'Inspected and isolated','partsUsed':'Seal','photoIds':[photo],'signatureId':sig};await api.call(p,'PATCH',b);final restored=AppApi();await restored.init();expect((await restored.call(p))['answers'],answers);
  expect((await restored.call(p+'/submit','POST',{'confirmed':true}))['result'],'Attention required');await restored.call(p+'/submit','POST',{'confirmed':true});expect((await restored.call('inspections?status=submitted') as List).length,1);await expectLater(restored.call(p,'PATCH',b),throwsException);
  final defects=await restored.call('defects') as List;expect(defects.length,1);final d='defects/'+defects.first['id']+'/transition';await restored.call(d,'POST',{'transition':'start','notes':'Replacement underway'});expect((await restored.call(d,'POST',{'transition':'resolve','notes':'Seal replaced'}))['status'],'resolved');await expectLater(restored.call(d,'POST',{'transition':'verify','notes':'Close work'}),throwsException);
  expect(utf8.decode((await restored.report(r['id'])).take(5).toList()),'%PDF-');expect(utf8.decode((await restored.qrPdf(a)).take(5).toList()),'%PDF-');
 });
 testWidgets('phone layout and required checklist validation at 320 pixels',(tester)async{
  final previousHandler=FlutterError.onError; FlutterError.onError=(details){debugPrint(details.toString());previousHandler?.call(details);};addTearDown(()=>FlutterError.onError=previousHandler);
  tester.view.physicalSize=const Size(320,760);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);final api=AppApi();await tester.runAsync(api.loadDemo);await api.loginDemo();await tester.pumpWidget(FyreboxApp(api:api));await tester.pumpAndSettle();expect(find.textContaining('Good day,'),findsOneWidget);expect(tester.takeException(),isNull);
  final s=Store(api);await s.refresh();final a=s.assets.first,t=s.checklists.firstWhere((t)=>t['category']==a['category']);final r=await api.call('inspections','POST',{'assetId':a['id'],'templateId':t['id']});await tester.pumpWidget(MaterialApp(home:InspectionPage(s:s,record:obj(r))));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Submit inspection'),500,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('Submit inspection'));await tester.pumpAndSettle();expect(find.textContaining('Answer every required'),findsWidgets);expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(seconds:1));
 });
}
