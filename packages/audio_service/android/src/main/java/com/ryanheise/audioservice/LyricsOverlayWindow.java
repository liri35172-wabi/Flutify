package com.ryanheise.audioservice;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.text.Layout;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.animation.LinearInterpolator;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Small draggable, non-focusable Android lyrics overlay owned by the active media service. */
final class LyricsOverlayWindow {
    private final Context context;
    private final WindowManager windowManager;
    private final LinearLayout root;
    private final TextView primary;
    private final TextView translation;
    private final OnePassTicker primaryTicker;
    private final OnePassTicker translationTicker;
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

        primary = new ContrastTextView(context);
        primary.setTextColor(textColor);
        // Keep lyrics readable over light or busy apps even when the surface is transparent.
        primary.setTextSize(18);
        primary.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        primary.setSingleLine(true);
        primary.setHorizontallyScrolling(true);
        primary.setEllipsize(null);
        primary.setMaxWidth(maxTextWidth());
        primary.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        primaryTicker = new OnePassTicker(primary);
        root.addView(primary, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        translation = new ContrastTextView(context);
        translation.setTextColor(0xFFE7E9EF);
        translation.setTextSize(12);
        translation.setSingleLine(true);
        translation.setHorizontallyScrolling(true);
        translation.setEllipsize(null);
        translation.setMaxWidth(maxTextWidth());
        translation.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        translationTicker = new OnePassTicker(translation);
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

    void setStyle(int color, int fontScale, boolean automatic) {
        textColor = automatic ? Color.WHITE : (color | 0xFF000000);
        this.fontScale = Math.max(80, Math.min(150, fontScale));
        boolean lightText = usesLightText(textColor);
        primary.setTextColor(textColor);
        primary.setTextSize(18f * this.fontScale / 100f);
        ((ContrastTextView) primary).setContrastOutline(true);
        translation.setTextColor(lightText ? 0xFFE7E9EF : 0xFF252A32);
        translation.setTextSize(12f * this.fontScale / 100f);
        ((ContrastTextView) translation).setContrastOutline(true);
        root.setBackground(transparentBackground ? null : background());
    }

    void show(String text, String translatedText, long remainingMs) {
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
        primaryTicker.show(text, remainingMs);
        translationTicker.show(nextTranslation, remainingMs);
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
        primaryTicker.cancel();
        translationTicker.cancel();
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

    /** Auto is a static, high-contrast treatment; it never samples another app's screen. */
    private final class ContrastTextView extends TextView {
        private boolean useContrastOutline = true;

        ContrastTextView(Context context) {
            super(context);
        }

        void setContrastOutline(boolean enabled) {
            useContrastOutline = enabled;
            getPaint().clearShadowLayer();
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            if (!useContrastOutline) {
                super.onDraw(canvas);
                return;
            }
            Paint textPaint = getPaint();
            Paint.Style originalStyle = textPaint.getStyle();
            float originalStrokeWidth = textPaint.getStrokeWidth();
            Paint.Join originalJoin = textPaint.getStrokeJoin();
            int originalColor = textPaint.getColor();
            textPaint.clearShadowLayer();
            textPaint.setStyle(Paint.Style.STROKE);
            textPaint.setStrokeJoin(Paint.Join.ROUND);
            // One thin opposing keyline keeps the glyph shape crisp. Stacking broad white
            // and black strokes made colored and black lyrics look swollen on-device.
            textPaint.setStrokeWidth(dp(1f));
            textPaint.setColor(usesLightText(originalColor) ? 0xE6000000 : 0xDFFFFFFF);
            super.onDraw(canvas);
            textPaint.setStyle(Paint.Style.FILL);
            textPaint.setColor(originalColor);
            super.onDraw(canvas);
            textPaint.setStyle(originalStyle);
            textPaint.setStrokeWidth(originalStrokeWidth);
            textPaint.setStrokeJoin(originalJoin);
        }
    }

    private int maxTextWidth() {
        int available = context.getResources().getDisplayMetrics().widthPixels - dp(48);
        return Math.max(dp(120), Math.min(dp(360), available));
    }

    /** A single bounded pass to the actual text end; unlike TextView marquee it never loops. */
    private static final class OnePassTicker {
        private final TextView view;
        private ValueAnimator animator;
        private Runnable pendingStart;
        private int generation;

        OnePassTicker(TextView view) {
            this.view = view;
        }

        void show(String text, long remainingMs) {
            cancel();
            final int token = generation;
            view.setText(text);
            view.scrollTo(0, 0);
            long dwellMs = Math.min(500L, Math.max(0L, remainingMs - 50L));
            pendingStart = () -> {
                pendingStart = null;
                if (token != generation || text.isEmpty()) return;
                Layout layout = view.getLayout();
                if (layout == null || layout.getLineCount() == 0) return;
                int viewport = view.getWidth() - view.getCompoundPaddingLeft()
                        - view.getCompoundPaddingRight();
                int distance = (int) Math.ceil(layout.getLineRight(0) - layout.getLineLeft(0) - viewport);
                if (distance <= 1) return;
                ValueAnimator next = ValueAnimator.ofInt(0, distance);
                animator = next;
                long motionMs = Math.max(50L, remainingMs - dwellMs);
                next.setDuration(motionMs);
                next.setInterpolator(new LinearInterpolator());
                next.addUpdateListener(value -> {
                    if (token == generation) view.scrollTo((int) value.getAnimatedValue(), 0);
                });
                next.start();
            };
            if (dwellMs == 0L) {
                view.post(pendingStart);
            } else {
                view.postDelayed(pendingStart, dwellMs);
            }
        }

        void cancel() {
            generation++;
            if (pendingStart != null) {
                view.removeCallbacks(pendingStart);
                pendingStart = null;
            }
            if (animator != null) {
                animator.cancel();
                animator = null;
            }
            view.scrollTo(0, 0);
        }
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
