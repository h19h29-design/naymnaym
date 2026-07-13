package com.h19h29.naymnaymlevelup;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class MealFeedbackPolicy {
    private static final Pattern ALLERGY_GROUP = Pattern.compile("\\(([0-9.,\\s]+)\\)");

    private MealFeedbackPolicy() {}

    static Set<Integer> parseAllergyCodes(String rawMenu) {
        Set<Integer> codes = new HashSet<>();
        if (rawMenu == null || rawMenu.isEmpty()) return codes;

        Matcher matcher = ALLERGY_GROUP.matcher(rawMenu);
        while (matcher.find()) {
            for (String value : matcher.group(1).split("[.,\\s]+")) {
                try {
                    if (!value.isEmpty()) codes.add(Integer.parseInt(value));
                } catch (NumberFormatException ignored) {
                    // Non-NEIS numeric text is ignored.
                }
            }
        }
        return codes;
    }

    static String normalizeSharedDate(String value) {
        if (value == null) return "";
        return value.matches("\\d{4}-\\d{2}-\\d{2}") ? value.replace("-", "") : value;
    }

    static boolean shouldAttemptSnapshotUpload(boolean registeredLink, boolean pending, int recordCount) {
        return registeredLink && pending;
    }

    static boolean needsInitialSnapshotUpload(boolean initialized, int recordCount) {
        return !initialized && recordCount > 0;
    }

    static boolean shouldClearPendingAfterSuccess(long uploadedRevision, long currentRevision) {
        return uploadedRevision == currentRevision;
    }

    static long snapshotRetryDelayMillis(int attempt) {
        int boundedAttempt = Math.max(1, Math.min(attempt, 5));
        return Math.min(30_000L, 2_000L * (1L << (boundedAttempt - 1)));
    }

    static BatchSelection safeBatch(List<MenuFeedbackItem> items, Set<Integer> selectedAllergyCodes) {
        List<String> recordedNames = new ArrayList<>();
        List<String> skippedNames = new ArrayList<>();
        Set<Integer> selected = selectedAllergyCodes == null
            ? Collections.emptySet()
            : new HashSet<>(selectedAllergyCodes);

        for (MenuFeedbackItem item : items) {
            boolean hasMarker = !item.allergyCodes.isEmpty();
            boolean intersects = !Collections.disjoint(item.allergyCodes, selected);
            boolean isRisk = hasMarker && (selected.isEmpty() || intersects);
            if (isRisk) {
                skippedNames.add(item.name);
            } else {
                recordedNames.add(item.name);
            }
        }
        return new BatchSelection(recordedNames, skippedNames);
    }

    static int childConnectedCount(boolean connected) {
        return connected ? 1 : 0;
    }

    static int parentConnectedCount(int storedChildren) {
        return Math.max(0, storedChildren);
    }

    static final class MenuFeedbackItem {
        final String name;
        final Set<Integer> allergyCodes;

        MenuFeedbackItem(String name, Set<Integer> allergyCodes) {
            this.name = name;
            this.allergyCodes = allergyCodes == null
                ? Collections.emptySet()
                : new HashSet<>(allergyCodes);
        }
    }

    static final class BatchSelection {
        final List<String> recordedNames;
        final List<String> skippedNames;

        BatchSelection(List<String> recordedNames, List<String> skippedNames) {
            this.recordedNames = Collections.unmodifiableList(new ArrayList<>(recordedNames));
            this.skippedNames = Collections.unmodifiableList(new ArrayList<>(skippedNames));
        }
    }
}
