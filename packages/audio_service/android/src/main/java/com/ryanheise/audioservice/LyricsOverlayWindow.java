package com.ryanheise.audioservice;

import android.content.Context;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Small draggable, non-focusable Android lyrics overlay owned by the active media service. */
final class LyricsOverlayWindow {
    private final Context context;
    private final WindowManager windowManager;
    private final LinearLayout root;
    private final TextView primary;
    private final TextView translation;
    private final WindowManager.LayoutParams params;
    private boolean attached;
    private float downRawX;
    private float downRawY;
    private int downX;
    private int downY;
    private String lastPrimary;
    private String lastTranslation;

    LyricsOverlayWindow(Context context) {
        this.context = context;
        this.windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(dp(18), dp(10), dp(18), dp(10));
        root.setBackground(background());
        root.setElevation(dp(8));
        root.setClickable(true);
        root.setFocusable(false);

        primary = new TextView(context);
        primary.setTextColor(Color.WHITE);
        primary.setTextSize(16);
        primary.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        primary.setSingleLine(true);
        primary.setEllipsize(android.text.TextUtils.TruncateAt.END);
        primary.setGravity(Gravity.CENTER);
        root.addView(primary, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        translation = new TextView(context);
        translation.setTextColor(0xFFD8D8D8);
        translation.setTextSize(12);
        translation.setSingleLine(true);
        translation.setEllipsize(android.text.TextUtils.TruncateAt.END);
        translation.setGravity(Gravity.CENTER);
        root.addView(translation, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        params.y = dp(72);
        root.setOnTouchListener(this::onTouch);
    }

    void show(String text, String translatedText) {
        if (text == null || text.trim().isEmpty()) {
            hide();
            return;
        }
        if (!attached) {
            try {
                windowManager.addView(root, params);
                attached = true;
            } catch (RuntimeException exception) {
                // Permission can be revoked while Flutify is in the background.
                attached = false;
                return;
            }
        }
        String nextTranslation = translatedText == null ? "" : translatedText.trim();
        if (!text.equals(lastPrimary)) primary.setText(text);
        if (!nextTranslation.equals(lastTranslation)) translation.setText(nextTranslation);
        translation.setVisibility(nextTranslation.isEmpty() ? View.GONE : View.VISIBLE);
        lastPrimary = text;
        lastTranslation = nextTranslation;
        try {
            windowManager.updateViewLayout(root, params);
        } catch (RuntimeException ignored) {
            attached = false;
        }
    }

    void hide() {
        if (!attached) return;
        try {
            windowManager.removeView(root);
        } catch (RuntimeException ignored) {
            // The system may already have removed the view after a permission change.
        }
        attached = false;
    }

    void dispose() {
        hide();
    }

    private boolean onTouch(View view, MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downRawX = event.getRawX();
                downRawY = event.getRawY();
                downX = params.x;
                downY = params.y;
                return true;
            case MotionEvent.ACTION_MOVE:
                params.x = downX + Math.round(event.getRawX() - downRawX);
                params.y = Math.max(dp(8), downY + Math.round(event.getRawY() - downRawY));
                if (attached) {
                    try {
                        windowManager.updateViewLayout(root, params);
                    } catch (RuntimeException ignored) {
                        attached = false;
                    }
                }
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                return true;
            default:
                return false;
        }
    }

    private GradientDrawable background() {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(0xCC202124);
        drawable.setCornerRadius(dp(24));
        drawable.setStroke(dp(1), 0x33FFFFFF);
        return drawable;
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
