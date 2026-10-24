package com.ansub.tvhome;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

// The remote's menu key (three lines) sends ALL_APPS, which Android hands only to a built-in home screen.
// With the stock one turned off nothing answers it, so this opens the TV's settings instead. It sees no
// other key and reads nothing on screen. install.sh turns it on.
public class KeyService extends AccessibilityService {
    @Override
    public boolean onKeyEvent(KeyEvent e) {
        // Logged so `adb logcat -s KeyService` shows which key a remote button sends.
        if (e.getAction() == KeyEvent.ACTION_DOWN) Log.i("KeyService", KeyEvent.keyCodeToString(e.getKeyCode()));
        if (e.getKeyCode() != KeyEvent.KEYCODE_ALL_APPS) return false;
        if (e.getAction() == KeyEvent.ACTION_UP) {
            try { startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); }
            catch (Exception ignored) {}
        }
        return true;
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {}
    @Override public void onInterrupt() {}
}
