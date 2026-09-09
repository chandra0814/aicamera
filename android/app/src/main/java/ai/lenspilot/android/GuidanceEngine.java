package ai.lenspilot.android;

import java.nio.ByteBuffer;
import java.util.Locale;
import java.util.ArrayList;
import java.util.List;

/** Local photographic rules; does not detect subjects or interpret reference images. */
public final class GuidanceEngine {
    private GuidanceEngine() {}
    public enum Light { UNKNOWN, DARK, BALANCED, BRIGHT }
    public enum Scene { GENERAL, PORTRAIT, LANDSCAPE, FOOD, NIGHT }

    public static Light measure(ByteBuffer plane, int width, int height, int rowStride, int pixelStride) {
        if (width <= 0 || height <= 0 || rowStride <= 0 || pixelStride <= 0) return Light.UNKNOWN;
        long sum = 0;
        int count = 0;
        int base = plane.position();
        int step = Math.max(1, Math.max(width, height) / 64);
        for (int y = 0; y < height; y += step) {
            for (int x = 0; x < width; x += step) {
                long index = (long) base + (long) y * rowStride + (long) x * pixelStride;
                if (index >= plane.limit()) continue;
                sum += plane.get((int) index) & 0xff;
                count++;
            }
        }
        if (count == 0) return Light.UNKNOWN;
        double mean = (double) sum / count;
        if (mean < 55) return Light.DARK;
        if (mean > 210) return Light.BRIGHT;
        return Light.BALANCED;
    }

    public static Scene sceneFor(String instruction, Scene selected) {
        String text = normalize(instruction);
        // Do not guess a scene from a negated request; retain the user's explicit selection.
        if (negated(text)) return selected;
        if (text.matches(".*\\b(night|dark|stars)\\b.*")) return Scene.NIGHT;
        if (text.matches(".*\\b(portrait|selfie|person|face)\\b.*")) return Scene.PORTRAIT;
        if (text.matches(".*\\b(food|meal|dish|coffee)\\b.*")) return Scene.FOOD;
        if (text.matches(".*\\b(landscape|mountain|sky|sunset)\\b.*")) return Scene.LANDSCAPE;
        return selected;
    }

    private static String normalize(String text) {
        return text == null ? "" : text.toLowerCase(Locale.ROOT).replaceAll("\\s+", " ").trim();
    }

    private static boolean negated(String text) {
        return text.matches(".*\\b(no|not|never|avoid|without|don.t)\\b.*");
    }

    private static List<String> requestIdeas(String instruction) {
        String text = normalize(instruction);
        List<String> ideas = new ArrayList<>();
        if (negated(text)) return ideas;
        if (text.contains("more sky")) ideas.add("Place the horizon lower in the frame to include more sky. Keep the phone level.");
        if (text.contains("cleaner background") || text.contains("less clutter")) ideas.add("Try a simpler backdrop and check the frame edges for distractions.");
        if (text.contains("brighter")) ideas.add("Try softer, brighter light on the subject while preserving detail in bright areas.");
        if (text.contains("natural skin") || text.contains("natural color") || text.contains("natural colour")) ideas.add("Use neutral daylight and avoid mixed colored lighting for natural tones.");
        if (text.contains("less background blur")) ideas.add("Use a wider view and keep the subject closer to the background for more visible detail.");
        return ideas;
    }

    public static boolean supportsRequest(String instruction) {
        return !requestIdeas(instruction).isEmpty() || sceneFor(instruction, Scene.GENERAL) != Scene.GENERAL;
    }

    public static String ideaForRequest(String instruction, Scene scene, boolean reference, int index) {
        List<String> requested = requestIdeas(instruction);
        int baseCount = reference ? 4 : 3;
        int slot = Math.floorMod(index, requested.size() + baseCount);
        return slot < requested.size() ? requested.get(slot) : idea(scene, reference, slot - requested.size());
    }

    public static String lightingTip(Light light, Scene scene) {
        if (light == Light.DARK) return scene == Scene.NIGHT
            ? "Frame looks dark. Brace the phone on a stable support and keep it still."
            : "Frame looks dark. Try a brighter position or turn toward a nearby light.";
        if (light == Light.BRIGHT) return "Frame looks bright. Try softer light or reframe away from the brightest area.";
        return null;
    }

    public static String idea(Scene scene, boolean reference, int index) {
        String[] ideas;
        switch (scene) {
            case PORTRAIT: ideas = new String[] {
                "Place the eyes near the upper grid line and leave room in the direction of the gaze.",
                "Try soft window light from the side for a natural portrait.",
                "Choose a simple background and leave space between the subject and it." }; break;
            case LANDSCAPE: ideas = new String[] {
                "Try placing the horizon on the lower third when the sky is the main subject.",
                "Include a nearby foreground detail to give the scene depth.",
                "Look for a path or edge that leads toward your main subject." }; break;
            case FOOD: ideas = new String[] {
                "Try an overhead view for a flat dish, or a lower angle for a tall one.",
                "Use soft side light and keep your phone's shadow off the plate.",
                "Remove distracting items from the edge of the frame." }; break;
            case NIGHT: ideas = new String[] {
                "Brace the phone on a stable support before pressing the shutter.",
                "Use an existing light source to separate your subject from the background.",
                "Try a wider composition without digital zoom to preserve detail." }; break;
            default: ideas = new String[] {
                "Choose one main subject and place it near a grid intersection.",
                "Try a simpler background so the subject stands out.",
                "Compare a wider view with a closer composition from a safe position." };
        }
        int count = ideas.length + (reference ? 1 : 0);
        int slot = Math.floorMod(index, count);
        if (slot == ideas.length) return "Compare subject size and empty space with your reference, then adjust the framing.";
        return ideas[slot];
    }
}
