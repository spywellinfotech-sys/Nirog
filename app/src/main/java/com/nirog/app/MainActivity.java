package com.nirog.app;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;

/**
 * Shows the bundled Nirog web app full screen.
 * The app lives in app/src/main/assets/www/index.html and works without a server.
 */
public class MainActivity extends Activity {

    private static final String START_URL = "file:///android_asset/www/index.html";
    private WebView webView;
    private String pendingAuth; // fragment of a nirog://auth#... sign-in return, delivered once the page is ready

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true); // the app keeps bookings and sign-ins in localStorage
        settings.setAllowFileAccess(true);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                deliverAuth();
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("file".equals(uri.getScheme())) {
                    return false; // stay inside the app
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

        captureAuth(getIntent());
        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        } else {
            webView.loadUrl(START_URL);
        }
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
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
