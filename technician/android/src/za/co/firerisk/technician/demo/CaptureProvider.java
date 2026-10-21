package za.co.firerisk.technician.demo;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;

public class CaptureProvider extends ContentProvider {
    private File photo(Uri uri) throws FileNotFoundException {
        if(!"/photo.jpg".equals(uri.getPath()))throw new FileNotFoundException();
        return new File(getContext().getCacheDir(),"inspection-camera.jpg");
    }
    @Override public boolean onCreate(){return true;}
    @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(photo(uri),ParcelFileDescriptor.parseMode(mode));
    }
    @Override public String getType(Uri uri){return "image/jpeg";}
    @Override public Cursor query(Uri uri,String[] projection,String selection,String[] selectionArgs,String order){
        try{File f=photo(uri);MatrixCursor c=new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE});c.addRow(new Object[]{f.getName(),f.length()});return c;}catch(Exception e){return null;}
    }
    @Override public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException();}
    @Override public int update(Uri uri,ContentValues values,String where,String[] args){return 0;}
    @Override public int delete(Uri uri,String where,String[] args){return 0;}
}
