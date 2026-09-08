import ai.lenspilot.android.GuidanceEngine;
import ai.lenspilot.android.GuidanceEngine.Light;
import ai.lenspilot.android.GuidanceEngine.Scene;
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
        check(GuidanceEngine.lightingTip(Light.UNKNOWN, Scene.GENERAL) == null, "no invented light assessment");
        check(GuidanceEngine.lightingTip(Light.DARK, Scene.NIGHT).contains("stable"), "night-specific advice");
        for (Scene scene : Scene.values()) {
            HashSet<String> ideas = new HashSet<>();
            for (int i = 0; i < 3; i++) ideas.add(GuidanceEngine.idea(scene, false, i));
            check(ideas.size() == 3, "three distinct ideas for " + scene);
            check(GuidanceEngine.idea(scene, false, 3).equals(GuidanceEngine.idea(scene, false, 0)), "idea cycling");
            check(GuidanceEngine.idea(scene, true, 3).contains("reference"), "reference comparison idea");
        }
        System.out.println("GuidanceEngine: all checks passed");
    }
    private static void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
    }
}
