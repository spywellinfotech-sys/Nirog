package com.nirog.app;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentValues;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import com.google.firebase.messaging.FirebaseMessaging;
import org.json.JSONObject;
import java.io.OutputStream;

/**
 * Shows the bundled Nirog web app full screen.
 * The app lives in app/src/main/assets/www/index.html and works without a server.
 */
public class MainActivity extends Activity {

    private static final String START_URL = "file:///android_asset/www/index.html";
    private WebView webView;
    private static MainActivity current; // lets the push service hand a new token to the open page
    private static final int FILE_REQ = 1001;
    private static final int MEDIA_REQ = 2002;
    private android.webkit.PermissionRequest pendingMedia; // camera/microphone request from the video call page
    private ValueCallback<Uri[]> filePathCallback; // pending file picker for <input type="file">
    private String pendingAuth; // fragment of a nirog://auth#... sign-in return, delivered once the page is ready



    /** Called by NirogMessagingService when Firebase issues a new token. */
    static void pushTokenChanged(String token) {
        final MainActivity a = current;
        if (a == null || a.webView == null || token == null) return;
        a.runOnUiThread(() -> a.webView.evaluateJavascript(
                "window.__nirogPush && window.__nirogPush(" + JSONObject.quote(token) + ")", null));
    }

    /** Lets the web app save a generated PDF into the phone's Downloads folder, open it, or share it on WhatsApp. Only local app pages can call it. */
    private class NativeBridge {
        private Uri store(String base64, String name) throws Exception {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || base64 == null || name == null) {
                return null;
            }
            byte[] bytes = Base64.decode(base64, Base64.DEFAULT);
            String safe = name.replaceAll("[^A-Za-z0-9._-]", "_");
            if (!safe.endsWith(".pdf")) safe = safe + ".pdf";
            ContentValues v = new ContentValues();
            v.put(MediaStore.MediaColumns.DISPLAY_NAME, safe);
            v.put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf");
            v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (uri == null) return null;
            try (OutputStream os = getContentResolver().openOutputStream(uri)) {
                if (os == null) return null;
                os.write(bytes);
            }
            return uri;
        }

        /** The phone's push token ("" until Firebase has issued one). The web app registers it for the signed-in user. */
        @JavascriptInterface
        public String pushToken() {
            return NirogMessagingService.savedToken(MainActivity.this);
        }

        @JavascriptInterface
        public boolean savePdf(String base64, String name) {
            try {
                final Uri uri = store(base64, name);
                if (uri == null) return false;
                runOnUiThread(() -> {
                    Toast.makeText(MainActivity.this, "Saved to Downloads", Toast.LENGTH_LONG).show();
                    try {
                        Intent view = new Intent(Intent.ACTION_VIEW);
                        view.setDataAndType(uri, "application/pdf");
                        view.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(view);
                    } catch (ActivityNotFoundException ignored) {
                        // no PDF viewer installed: the file is still in Downloads
                    }
                });
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        /** Saves the PDF, then opens WhatsApp with it attached (to the given number when WhatsApp accepts it), or the share sheet. */
        @JavascriptInterface
        public boolean sharePdf(String base64, String name, String phone, String text) {
            try {
                final Uri uri = store(base64, name);
                if (uri == null) return false;
                final String number = phone != null && phone.matches("[0-9]{10,15}") ? phone : null;
                final String msg = text == null ? "" : text;
                runOnUiThread(() -> {
                    Intent send = new Intent(Intent.ACTION_SEND);
                    send.setType("application/pdf");
                    send.putExtra(Intent.EXTRA_STREAM, uri);
                    send.putExtra(Intent.EXTRA_TEXT, msg);
                    send.setClipData(ClipData.newRawUri("prescription", uri));
                    send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    Intent wa = new Intent(send);
                    wa.setPackage("com.whatsapp");
                    if (number != null) wa.putExtra("jid", number + "@s.whatsapp.net");
                    try {
                        startActivity(wa);
                    } catch (ActivityNotFoundException e) {
                        try {
                            startActivity(Intent.createChooser(send, "Share prescription"));
                        } catch (ActivityNotFoundException ignored) {
                            // nothing can share a PDF
                        }
                    }
                });
                return true;
            } catch (Exception e) {
                return false;
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        current = this;
        webView = new WebView(this);
        // Android 15 and newer draw apps edge to edge. The WebView sits in a container that keeps it clear of the status bar,
        // camera cutout, navigation bar and keyboard; the container (not the WebView) takes the insets so they cannot be lost.
        final android.widget.FrameLayout box = new android.widget.FrameLayout(this);
        box.setBackgroundColor(0xFFFFF8F0);
        box.addView(webView, new android.widget.FrameLayout.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(box);
        if (Build.VERSION.SDK_INT >= 35) {
            box.setOnApplyWindowInsetsListener((v, ins) -> {
                android.graphics.Insets b = ins.getInsets(android.view.WindowInsets.Type.systemBars() | android.view.WindowInsets.Type.displayCutout() | android.view.WindowInsets.Type.ime());
                v.setPadding(b.left, b.top, b.right, b.bottom);
                return android.view.WindowInsets.CONSUMED;
            });
            box.post(box::requestApplyInsets);
        }

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        // Lets the web app know which build it runs in, so the admin can force an update.
        try {
            @SuppressWarnings("deprecation")
            int build = getPackageManager().getPackageInfo(getPackageName(), 0).versionCode;
            settings.setUserAgentString(settings.getUserAgentString() + " NirogApp/" + build);
        } catch (Exception ignored) {
            // no build number: the update check stays off
        }
        webView.addJavascriptInterface(new NativeBridge(), "NirogNative");
        // The video call page plays the other person's voice without a tap; WebView blocks that by default.
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setDomStorageEnabled(true); // the app keeps bookings and sign-ins in localStorage
        settings.setAllowFileAccess(true);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);

        // Without this, "Choose file" buttons in the web app do nothing inside an Android WebView.
        webView.setWebChromeClient(new WebChromeClient() {
            /** The video call page asks for camera and microphone: pass the request on to Android's own permission prompt. */
            @Override
            public void onPermissionRequest(final android.webkit.PermissionRequest request) {
                runOnUiThread(() -> {
                    java.util.ArrayList<String> need = new java.util.ArrayList<>();
                    for (String r : request.getResources()) {
                        if (android.webkit.PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) need.add(android.Manifest.permission.CAMERA);
                        if (android.webkit.PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) need.add(android.Manifest.permission.RECORD_AUDIO);
                    }
                    java.util.ArrayList<String> missing = new java.util.ArrayList<>();
                    for (String perm : need) {
                        if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) missing.add(perm);
                    }
                    if (missing.isEmpty()) {
                        request.grant(request.getResources());
                    } else {
                        if (pendingMedia != null) pendingMedia.deny();
                        pendingMedia = request;
                        requestPermissions(missing.toArray(new String[0]), MEDIA_REQ);
                    }
                });
            }

            @Override
            public void onPermissionRequestCanceled(android.webkit.PermissionRequest request) {
                if (pendingMedia == request) pendingMedia = null;
            }

            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;
                try {
                    startActivityForResult(params.createIntent(), FILE_REQ);
                } catch (ActivityNotFoundException e) {
                    filePathCallback = null;
                    return false;
                }
                return true;
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                deliverAuth();
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("file".equals(uri.getScheme()) || !request.isForMainFrame()) {
                    return false; // stay inside the app (the video call page is a frame inside the app)
                }
                // Google Maps, phone and mail links open in the matching Android app.
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri));
                } catch (ActivityNotFoundException ignored) {
                    // no app can open this link
                }
                return true;
            }
        });

        setVolumeControlStream(android.media.AudioManager.STREAM_MUSIC);
        startPush();
        captureAuth(getIntent());
        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        } else {
            webView.loadUrl(START_URL);
        }
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        super.onRequestPermissionsResult(code, perms, results);
        if (code != MEDIA_REQ || pendingMedia == null) return;
        android.webkit.PermissionRequest req = pendingMedia;
        pendingMedia = null;
        boolean ok = results.length > 0;
        for (int r : results) if (r != PackageManager.PERMISSION_GRANTED) ok = false;
        if (ok) req.grant(req.getResources()); else req.deny();
    }

    /** Creates the notification channel, asks for permission on Android 13+, and fetches the push token. */
    private void startPush() {
        try {
            NirogMessagingService.ensureChannel(this);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                    && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 2001);
            }
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                if (task.isSuccessful() && task.getResult() != null) {
                    NirogMessagingService.saveToken(MainActivity.this, task.getResult());
                    pushTokenChanged(task.getResult());
                }
            });
        } catch (Exception ignored) {
            // push is optional: the app works without it
        }
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == FILE_REQ) {
            if (filePathCallback != null) {
                filePathCallback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                filePathCallback = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        captureAuth(intent);
        deliverAuth();
    }

    private void captureAuth(Intent intent) {
        Uri data = intent == null ? null : intent.getData();
        if (data != null && "nirog".equals(data.getScheme()) && "auth".equals(data.getHost())) {
            String frag = data.getEncodedFragment();
            String query = data.getEncodedQuery();
            pendingAuth = frag != null ? frag : (query != null ? query : "");
        }
    }

    private void deliverAuth() {
        if (pendingAuth == null || webView == null) return;
        String f = pendingAuth;
        pendingAuth = null;
        webView.evaluateJavascript(
                "window.__nirogAuth && window.__nirogAuth(" + JSONObject.quote(f) + ")", null);
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        webView.saveState(outState);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        // Let the web app step back first (doctor page to list, and so on). Exit when it has nothing to go back to.
        webView.evaluateJavascript(
                "(function(){return window.__nirogBack ? window.__nirogBack() : false;})()",
                value -> {
                    if (!"true".equals(value)) {
                        MainActivity.super.onBackPressed();
                    }
                });
    }

    @Override
    protected void onDestroy() {
        if (current == this) current = null;
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
