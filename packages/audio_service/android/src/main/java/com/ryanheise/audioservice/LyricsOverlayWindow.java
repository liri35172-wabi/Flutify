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
    private boolean clickThrough;
    private boolean transparentBackground;
    private int textColor = Color.WHITE;
    private int fontScale = 100;
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
        root.setPadding(dp(20), dp(11), dp(20), dp(11));
        root.setBackground(background());
        root.setElevation(dp(10));
        root.setClickable(true);
        root.setFocusable(false);

        primary = new TextView(context);
        primary.setTextColor(textColor);
        // Keep lyrics readable over light or busy apps even when the surface is transparent.
        primary.setShadowLayer(dp(1.25f), 0f, dp(1f), 0xA8000000);
        primary.setTextSize(18);
        primary.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        primary.setSingleLine(true);
        primary.setEllipsize(android.text.TextUtils.TruncateAt.MARQUEE);
        primary.setMarqueeRepeatLimit(-1);
        primary.setSelected(true);
        primary.setMaxWidth(maxTextWidth());
        primary.setGravity(Gravity.CENTER);
        root.addView(primary, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        translation = new TextView(context);
        translation.setTextColor(0xFFE7E9EF);
        translation.setShadowLayer(dp(1.25f), 0f, dp(1f), 0xA8000000);
        translation.setTextSize(12);
        translation.setSingleLine(true);
        translation.setEllipsize(android.text.TextUtils.TruncateAt.MARQUEE);
        translation.setMarqueeRepeatLimit(-1);
        translation.setSelected(true);
        translation.setMaxWidth(maxTextWidth());
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

    /** Changes overlay interaction and appearance without resetting its saved position. */
    void setOptions(boolean clickThrough, boolean transparentBackground) {
        boolean changed = this.clickThrough != clickThrough
                || this.transparentBackground != transparentBackground;
        this.clickThrough = clickThrough;
        this.transparentBackground = transparentBackground;
        if (changed) {
            root.setBackground(transparentBackground ? null : background());
            root.setClickable(!clickThrough);
        }
        int flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
        if (clickThrough) flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE;
        params.flags = flags;
        // Android 12+ blocks touches through highly-obscuring application overlays.
        params.alpha = clickThrough ? 0.65f : 1f;
        if (changed && attached) {
            try {
                windowManager.updateViewLayout(root, params);
            } catch (RuntimeException ignored) {
                attached = false;
            }
        }
    }

    void setStyle(int color, int fontScale) {
        textColor = color | 0xFF000000;
        this.fontScale = Math.max(80, Math.min(150, fontScale));
        primary.setTextColor(textColor);
        primary.setTextSize(18f * this.fontScale / 100f);
        boolean lightText = usesLightText(textColor);
        int edgeColor = lightText ? 0xF0000000 : 0xF0FFFFFF;
        primary.setShadowLayer(dp(1.25f), 0f, dp(1f), (edgeColor & 0x00FFFFFF) | 0xA8000000);
        translation.setTextColor(lightText ? 0xFFE7E9EF : 0xFF252A32);
        translation.setShadowLayer(dp(1.25f), 0f, dp(1f), (edgeColor & 0x00FFFFFF) | 0xA8000000);
        translation.setTextSize(12f * this.fontScale / 100f);
        root.setBackground(transparentBackground ? null : background());
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
        if (!text.equals(lastPrimary)) setMarqueeText(primary, text);
        if (!nextTranslation.equals(lastTranslation)) setMarqueeText(translation, nextTranslation);
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

    private int maxTextWidth() {
        int available = context.getResources().getDisplayMetrics().widthPixels - dp(48);
        return Math.max(dp(120), Math.min(dp(360), available));
    }

    private void setMarqueeText(TextView textView, String text) {
        textView.setSelected(false);
        textView.setText(text);
        textView.setSelected(true);
    }

    private GradientDrawable background() {
        GradientDrawable drawable = new GradientDrawable();
        boolean lightText = usesLightText(textColor);
        drawable.setColor(lightText ? 0xD91A1E27 : 0xEAF5F6FA);
        drawable.setCornerRadius(dp(20));
        drawable.setStroke(dp(1), lightText ? 0x44FFFFFF : 0x44353A45);
        return drawable;
    }

    private static boolean usesLightText(int color) {
        int red = Color.red(color);
        int green = Color.green(color);
        int blue = Color.blue(color);
        return red * 299 + green * 587 + blue * 114 >= 128000;
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
