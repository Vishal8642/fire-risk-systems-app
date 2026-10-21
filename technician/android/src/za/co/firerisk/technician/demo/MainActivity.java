package za.co.firerisk.technician.demo;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.WindowInsets;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.JsResult;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;

public class MainActivity extends Activity {
    private static final String HOST = "frs-technician.local";
    private static final int REQUEST_FILES = 101, REQUEST_SAVE = 102, REQUEST_CAMERA = 103;
    private WebView web;
    private ValueCallback<Uri[]> fileCallback;
    private PermissionRequest cameraRequest;
    private boolean pickerAfterPermission;
    private Uri captureUri;
    private byte[] pendingSave;
    private long lastBack;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(28,51,40));
        getWindow().setNavigationBarColor(Color.rgb(28,51,40));
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(28,51,40));
        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(247,248,243));
        root.addView(web, new FrameLayout.LayoutParams(-1,-1));
        if (Build.VERSION.SDK_INT >= 35) {
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((v,insets) -> {
                android.graphics.Insets inset = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
                v.setPadding(inset.left,inset.top,inset.right,inset.bottom);
                return insets;
            });
        }
        setContentView(root);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setSupportMultipleWindows(false);
        web.setOverScrollMode(WebView.OVER_SCROLL_NEVER);
        WebView.setWebContentsDebuggingEnabled(true);
        web.addJavascriptInterface(new Downloads(),"AndroidBridge");
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri=request.getUrl();
                if (!"https".equals(uri.getScheme()) || !HOST.equals(uri.getHost())) return denied();
                String path=uri.getPath();
                if (path==null || path.equals("/")) path="/index.html";
                if (path.contains("..") || path.contains("\\") || !"GET".equals(request.getMethod())) return denied();
                String file=path.substring(1),mime="application/octet-stream";
                if(file.endsWith(".html")) mime="text/html";
                else if(file.endsWith(".js")) mime="application/javascript";
                else if(file.endsWith(".css")) mime="text/css";
                else if(file.endsWith(".svg")) mime="image/svg+xml";
                else if(file.endsWith(".png")) mime="image/png";
                else if(file.endsWith(".json")) mime="application/json";
                try {
                    HashMap<String,String> headers=new HashMap<>();
                    headers.put("Cache-Control","no-cache");
                    headers.put("X-Content-Type-Options","nosniff");
                    headers.put("Content-Security-Policy","default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self' blob: data:; object-src 'none'; base-uri 'none'");
                    return new WebResourceResponse(mime,"UTF-8",200,"OK",headers,getAssets().open(file));
                } catch(IOException error) { return denied(); }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request) {
                return !HOST.equals(request.getUrl().getHost()) || !"https".equals(request.getUrl().getScheme());
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage message) {
                android.util.Log.d("FRSTechnician",message.message()+" @ "+message.lineNumber());
                return true;
            }
            @Override public boolean onJsConfirm(WebView view,String url,String message,JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                    .setPositiveButton("Continue",(d,w)->result.confirm())
                    .setNegativeButton("Cancel",(d,w)->result.cancel())
                    .setOnCancelListener(d->result.cancel()).show();
                return true;
            }
            @Override public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(()->{
                    if (!HOST.equals(request.getOrigin().getHost())) {request.deny();return;}
                    boolean video=false;
                    for(String resource:request.getResources()) if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource))video=true;
                    if(!video){request.deny();return;}
                    if(checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)
                        request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                    else {cameraRequest=request;requestPermissions(new String[]{Manifest.permission.CAMERA},REQUEST_CAMERA);}
                });
            }
            @Override public void onPermissionRequestCanceled(PermissionRequest request) {
                if(cameraRequest==request) cameraRequest=null;
            }
            @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params) {
                if(fileCallback!=null)fileCallback.onReceiveValue(null);
                fileCallback=callback;
                if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){
                    pickerAfterPermission=true;
                    requestPermissions(new String[]{Manifest.permission.CAMERA},REQUEST_CAMERA);
                }else showImagePicker(true);
                return true;
            }
        });
        web.loadUrl("https://"+HOST+"/index.html");
    }
    private WebResourceResponse denied(){
        return new WebResourceResponse("text/plain","UTF-8",404,"Not found",new HashMap<>(),new ByteArrayInputStream(new byte[0]));
    }
    private void showImagePicker(boolean cameraAllowed){
        try {
            Intent gallery=new Intent(Intent.ACTION_GET_CONTENT);
            gallery.setType("image/*");
            gallery.addCategory(Intent.CATEGORY_OPENABLE);
            gallery.putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);
            Intent chooser=Intent.createChooser(gallery,"Add inspection evidence");
            if(cameraAllowed){
                File f=new File(getCacheDir(),"inspection-camera.jpg");
                if(f.exists())f.delete();
                captureUri=Uri.parse("content://"+getPackageName()+".capture/photo.jpg");
                Intent camera=new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                camera.putExtra(MediaStore.EXTRA_OUTPUT,captureUri);
                camera.setClipData(ClipData.newRawUri("Inspection photo",captureUri));
                camera.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                if(camera.resolveActivity(getPackageManager())!=null)chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS,new Intent[]{camera});
            }
            startActivityForResult(chooser,REQUEST_FILES);
        }catch(Exception e){if(fileCallback!=null)fileCallback.onReceiveValue(null);fileCallback=null;toast("No image picker is available on this device.");}
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] results){
        super.onRequestPermissionsResult(requestCode,permissions,results);
        if(requestCode!=REQUEST_CAMERA)return;
        boolean granted=results.length>0&&results[0]==PackageManager.PERMISSION_GRANTED;
        if(cameraRequest!=null){if(granted)cameraRequest.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});else cameraRequest.deny();cameraRequest=null;}
        if(pickerAfterPermission){pickerAfterPermission=false;showImagePicker(granted);}
    }
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);
        if(requestCode==REQUEST_FILES&&fileCallback!=null){
            ArrayList<Uri> files=new ArrayList<>();
            if(resultCode==RESULT_OK){
                if(data!=null&&data.getClipData()!=null){ClipData clip=data.getClipData();for(int i=0;i<Math.min(4,clip.getItemCount());i++)files.add(clip.getItemAt(i).getUri());}
                else if(data!=null&&data.getData()!=null)files.add(data.getData());
                else if(captureUri!=null&&new File(getCacheDir(),"inspection-camera.jpg").length()>0)files.add(captureUri);
            }
            fileCallback.onReceiveValue(files.isEmpty()?null:files.toArray(new Uri[0]));fileCallback=null;captureUri=null;
        }else if(requestCode==REQUEST_SAVE&&pendingSave!=null){
            if(resultCode==RESULT_OK&&data!=null&&data.getData()!=null){try(OutputStream out=getContentResolver().openOutputStream(data.getData())){if(out==null)throw new IOException();out.write(pendingSave);toast("File saved.");}catch(Exception e){toast("The file could not be saved.");}}
            pendingSave=null;
        }
    }
    private void toast(String text){runOnUiThread(()->Toast.makeText(this,text,Toast.LENGTH_LONG).show());}
    public class Downloads {
        @JavascriptInterface public void saveFile(String rawName,String rawMime,String encoded){
            if(encoded==null||encoded.length()>28*1024*1024){toast("File is too large to save.");return;}
            String name=rawName==null?"FRS_Download.pdf":rawName.replaceAll("[^A-Za-z0-9._-]","_");
            if(name.length()>170)name=name.substring(name.length()-170);
            final String safeName=name;
            final String mime;
            String lower=name.toLowerCase(Locale.ROOT);
            if(lower.endsWith(".pdf"))mime="application/pdf";
            else if(lower.endsWith(".xlsx"))mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            else if(lower.endsWith(".csv"))mime="text/csv";
            else if(lower.endsWith(".svg"))mime="image/svg+xml";
            else if(lower.endsWith(".json"))mime="application/json";
            else {toast("Unsupported download type.");return;}
            final byte[] bytes;
            try{bytes=Base64.decode(encoded,Base64.DEFAULT);}catch(Exception e){toast("Download data could not be read.");return;}
            if(Build.VERSION.SDK_INT>=29){
                new Thread(()->{
                    Uri uri=null;
                    try{
                        ContentValues values=new ContentValues();values.put(MediaStore.Downloads.DISPLAY_NAME,safeName);values.put(MediaStore.Downloads.MIME_TYPE,mime);values.put(MediaStore.Downloads.RELATIVE_PATH,Environment.DIRECTORY_DOWNLOADS+"/FireRiskSystems");values.put(MediaStore.Downloads.IS_PENDING,1);
                        uri=getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values);
                        if(uri==null)throw new IOException();
                        try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException();out.write(bytes);}
                        ContentValues done=new ContentValues();done.put(MediaStore.Downloads.IS_PENDING,0);getContentResolver().update(uri,done,null,null);
                        toast("Saved to Downloads / FireRiskSystems");
                    }catch(Exception e){if(uri!=null)getContentResolver().delete(uri,null,null);toast("File could not be saved. Please try again.");}
                },"frs-download").start();
            }else runOnUiThread(()->{
                pendingSave=bytes;
                Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType(mime);intent.putExtra(Intent.EXTRA_TITLE,safeName);
                try{startActivityForResult(intent,REQUEST_SAVE);}catch(Exception e){pendingSave=null;toast("No document saving app is available.");}
            });
        }
    }
    @Override public void onBackPressed(){
        web.evaluateJavascript("window.frsNativeBack ? window.frsNativeBack() : false",handled->{
            if("true".equals(handled))return;
            if(System.currentTimeMillis()-lastBack<2000){super.onBackPressed();return;}
            lastBack=System.currentTimeMillis();toast("Press back again to close the demo.");
        });
    }
    @Override protected void onDestroy(){
        if(fileCallback!=null)fileCallback.onReceiveValue(null);
        if(cameraRequest!=null)cameraRequest.deny();
        web.evaluateJavascript("if(window.stopCamera)stopCamera();",null);
        web.removeJavascriptInterface("AndroidBridge");web.destroy();super.onDestroy();
    }
}
