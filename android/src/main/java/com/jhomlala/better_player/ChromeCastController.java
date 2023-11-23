package com.jhomlala.better_player;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.util.Log;
import android.view.ContextThemeWrapper;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.mediarouter.app.MediaRouteButton;

import com.google.android.gms.cast.framework.SessionManager;
import com.google.android.gms.common.api.PendingResult;
import com.google.android.gms.cast.MediaInfo;
import com.google.android.gms.cast.MediaLoadOptions;
import com.google.android.gms.cast.framework.CastButtonFactory;
import com.google.android.gms.cast.framework.CastContext;
import com.google.android.gms.cast.framework.Session;
import com.google.android.gms.cast.framework.SessionManagerListener;
import com.google.android.gms.common.api.Status;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

public class ChromeCastController implements SessionManagerListener<Session>, PlatformView, MethodChannel.MethodCallHandler, PendingResult.StatusListener {
    final BinaryMessenger binaryMessenger;
    final int viewId;
    final Context context;
    MethodChannel methodChannel;
    MediaRouteButton mediaRouteButton;
    SessionManager sessionManager;

    ChromeCastController(BinaryMessenger binaryMessenger, int viewId, Context context) {
        this.binaryMessenger = binaryMessenger;
        this.viewId = viewId;
        this.context = context;
         methodChannel = new MethodChannel(binaryMessenger, "flutter_video_cast/chromeCast_"+viewId);
        mediaRouteButton = new MediaRouteButton(context);
        mediaRouteButton.setRemoteIndicatorDrawable(new ColorDrawable(Color.TRANSPARENT));
        sessionManager =  CastContext.getSharedInstance().getSessionManager();
        CastButtonFactory.setUpMediaRouteButton(context, mediaRouteButton);
        methodChannel.setMethodCallHandler(this);
        Log.d("ChromeCast","Controller created for id"+viewId);
    }

    @Override
    public void onSessionStarting(Session session) {

    }

    @Override
    public void onSessionStarted(Session session, String s) {
        methodChannel.invokeMethod("chromeCast#didStartSession", null);
    }

    @Override
    public void onSessionStartFailed(Session session, int i) {

    }

    @Override
    public void onSessionEnding(Session session) {

    }

    @Override
    public void onSessionEnded(Session session, int i) {
        methodChannel.invokeMethod("chromeCast#didEndSession", null);
    }

    @Override
    public void onSessionResuming(Session session, String s) {

    }

    @Override
    public void onSessionResumed(Session session, boolean b) {

    }

    @Override
    public void onSessionResumeFailed(Session session, int i) {

    }

    @Override
    public void onSessionSuspended(Session session, int i) {

    }

    @Override
    public void onComplete(Status status) {

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if(call.method.equals("chromeCast#click")){
            Log.d("ChromeCast", "CLICK CALLED");
            mediaRouteButton.performClick();
            result.success(null);
        }
    }

    @Override
    public View getView() {
        return mediaRouteButton;
    }

    @Override
    public void onFlutterViewAttached(@NonNull View flutterView) {

    }

    @Override
    public void onFlutterViewDetached() {

    }

    @Override
    public void dispose() {

    }

    @Override
    public void onInputConnectionLocked() {

    }

    @Override
    public void onInputConnectionUnlocked() {

    }
}