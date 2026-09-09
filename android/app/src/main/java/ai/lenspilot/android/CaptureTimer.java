package ai.lenspilot.android;

/** Monotonic, one-shot timer. Lifecycle changes cancel instead of taking a late photo. */
public final class CaptureTimer {
    private long deadline = -1;
    public boolean start(int seconds, long now) {
        if (deadline >= 0 || (seconds != 0 && seconds != 3 && seconds != 10)) return false;
        deadline = now + seconds * 1000L;
        return true;
    }
    public boolean isActive() { return deadline >= 0; }
    public int remainingSeconds(long now) {
        return deadline < 0 ? 0 : (int) Math.max(0, (deadline - now + 999) / 1000);
    }
    public boolean consumeDue(long now, boolean canCapture) {
        if (!canCapture) { cancel(); return false; }
        if (deadline < 0 || now < deadline) return false;
        cancel();
        return true;
    }
    public void cancel() { deadline = -1; }
}
