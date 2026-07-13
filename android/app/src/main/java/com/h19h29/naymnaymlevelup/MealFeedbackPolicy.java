package com.h19h29.naymnaymlevelup;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class MealFeedbackPolicy {
    private MealFeedbackPolicy() {}

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
