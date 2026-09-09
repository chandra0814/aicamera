import ai.lenspilot.android.GuidanceEngine;
import ai.lenspilot.android.GuidanceEngine.Light;
import ai.lenspilot.android.GuidanceEngine.Scene;
import ai.lenspilot.android.CaptureTimer;
import java.nio.ByteBuffer;
import java.util.HashSet;

public final class GuidanceEngineTest {
    public static void main(String[] args) {
        check(GuidanceEngine.measure(ByteBuffer.wrap(new byte[] {0, 20, 30, 40}), 2, 2, 2, 1) == Light.DARK, "dark frame");
        check(GuidanceEngine.measure(ByteBuffer.wrap(new byte[] {(byte) 240, (byte) 255}), 2, 1, 2, 1) == Light.BRIGHT, "unsigned luminance");
        check(GuidanceEngine.measure(ByteBuffer.wrap(new byte[] {120, 0, 120, 0, 0, 120, 0, 120}), 2, 2, 5, 2) == Light.BALANCED, "row padding and pixel stride");
        ByteBuffer offset = ByteBuffer.wrap(new byte[] {0, 120, 120});
        offset.position(1);
        check(GuidanceEngine.measure(offset, 2, 1, 2, 1) == Light.BALANCED, "buffer offset");
        check(offset.position() == 1, "buffer position preserved");
        check(GuidanceEngine.measure(ByteBuffer.allocate(0), 2, 2, 2, 1) == Light.UNKNOWN, "empty frame");
        check(GuidanceEngine.measure(ByteBuffer.allocate(4), 0, 2, 2, 1) == Light.UNKNOWN, "invalid dimensions");
        check(GuidanceEngine.sceneFor("NIGHT PORTRAIT", Scene.GENERAL) == Scene.NIGHT, "night priority");
        check(GuidanceEngine.sceneFor("coffee photo", Scene.GENERAL) == Scene.FOOD, "food intent");
        check(GuidanceEngine.sceneFor("a skyline", Scene.PORTRAIT) == Scene.PORTRAIT, "whole words only");
        check(GuidanceEngine.sceneFor("", Scene.LANDSCAPE) == Scene.LANDSCAPE, "manual scene fallback");
        check(GuidanceEngine.sceneFor("not a night portrait", Scene.FOOD) == Scene.FOOD, "negation keeps manual scene");
        check(GuidanceEngine.sceneFor("A\nPORTRAIT", Scene.GENERAL) == Scene.PORTRAIT, "multiline request");
        check(GuidanceEngine.sceneFor(null, Scene.GENERAL) == Scene.GENERAL, "null request");
        check(GuidanceEngine.ideaForRequest("more sky", Scene.LANDSCAPE, false, 0).contains("horizon lower"), "sky request changes advice");
        check(GuidanceEngine.ideaForRequest("cleaner background", Scene.PORTRAIT, false, 0).contains("backdrop"), "background request");
        check(GuidanceEngine.ideaForRequest("natural skin", Scene.PORTRAIT, false, 0).contains("neutral daylight"), "natural tones request");
        check(GuidanceEngine.supportsRequest("less background blur"), "depth request");
        check(!GuidanceEngine.supportsRequest("make it luxury"), "unsupported request is explicit");
        check(!GuidanceEngine.supportsRequest("do not make it brighter"), "negated brightness not inverted");
        check(!GuidanceEngine.supportsRequest(""), "empty request is not interpreted");
        check(GuidanceEngine.lightingTip(Light.UNKNOWN, Scene.GENERAL) == null, "no invented light assessment");
        check(GuidanceEngine.lightingTip(Light.DARK, Scene.NIGHT).contains("stable"), "night-specific advice");
        for (Scene scene : Scene.values()) {
            HashSet<String> ideas = new HashSet<>();
            for (int i = 0; i < 3; i++) ideas.add(GuidanceEngine.idea(scene, false, i));
            check(ideas.size() == 3, "three distinct ideas for " + scene);
            check(GuidanceEngine.idea(scene, false, 3).equals(GuidanceEngine.idea(scene, false, 0)), "idea cycling");
            check(GuidanceEngine.idea(scene, true, 3).contains("reference"), "reference comparison idea");
        }
        CaptureTimer timer = new CaptureTimer();
        check(timer.start(3, 100), "start timer");
        check(!timer.start(3, 200), "double press does not schedule a second capture");
        check(timer.remainingSeconds(1099) == 3, "countdown rounds up");
        check(!timer.consumeDue(3099, true), "never capture early");
        check(timer.consumeDue(3100, true), "capture at deadline");
        check(!timer.consumeDue(3101, true), "capture exactly once");
        check(timer.start(10, 4000), "ten second timer");
        timer.cancel();
        check(!timer.consumeDue(20000, true), "cancel prevents delayed capture");
        check(timer.start(3, 20000), "restart");
        check(!timer.consumeDue(23000, false) && !timer.isActive(), "permission or lifecycle loss cancels");
        check(!timer.start(-1, 0) && !timer.start(5, 0), "unsupported timer values rejected");
        check(timer.start(0, 0) && timer.consumeDue(0, true), "immediate capture");
        System.out.println("GuidanceEngine and CaptureTimer: all checks passed");
    }
    private static void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
    }
}
