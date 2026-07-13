package com.h19h29.naymnaymlevelup;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class MealSnapshotLedger {
    private static final int MAX_RECORDS = 200;

    private final List<Entry> latestMeals = new ArrayList<>();
    private final List<Entry> challengeEntries = new ArrayList<>();

    boolean record(Entry entry) {
        removeMealState(entry.mealKey());
        latestMeals.add(0, entry);
        trim(latestMeals);

        if (containsAction(entry.actionKey())) {
            return false;
        }
        challengeEntries.add(0, entry);
        trim(challengeEntries);
        return true;
    }

    void restoreLatest(Entry entry) {
        if (!containsMeal(entry.mealKey())) {
            latestMeals.add(entry);
            trim(latestMeals);
        }
    }

    void restoreChallenge(Entry entry) {
        if (!containsAction(entry.actionKey())) {
            challengeEntries.add(entry);
            trim(challengeEntries);
        }
    }

    boolean hasAction(String date, String menuName, String eatingStatus) {
        return containsAction(Entry.actionKey(date, menuName, eatingStatus));
    }

    List<Entry> latestMeals() {
        return Collections.unmodifiableList(new ArrayList<>(latestMeals));
    }

    List<Entry> challengeEntries() {
        return Collections.unmodifiableList(new ArrayList<>(challengeEntries));
    }

    private boolean containsMeal(String key) {
        for (Entry entry : latestMeals) {
            if (entry.mealKey().equals(key)) return true;
        }
        return false;
    }

    private boolean containsAction(String key) {
        for (Entry entry : challengeEntries) {
            if (entry.actionKey().equals(key)) return true;
        }
        return false;
    }

    private void removeMealState(String key) {
        for (int index = latestMeals.size() - 1; index >= 0; index--) {
            if (latestMeals.get(index).mealKey().equals(key)) {
                latestMeals.remove(index);
            }
        }
    }

    private void trim(List<Entry> entries) {
        while (entries.size() > MAX_RECORDS) {
            entries.remove(entries.size() - 1);
        }
    }

    static final class Entry {
        final String mealId;
        final String challengeId;
        final String date;
        final String menuName;
        final String eatingStatus;
        final List<String> difficultyReasons;
        final Set<Integer> allergyCodes;
        final int gainedExp;
        final List<String> nutrients;
        final String createdAt;

        Entry(
            String mealId,
            String challengeId,
            String date,
            String menuName,
            String eatingStatus,
            List<String> difficultyReasons,
            Set<Integer> allergyCodes,
            int gainedExp,
            List<String> nutrients,
            String createdAt
        ) {
            this.mealId = mealId;
            this.challengeId = challengeId;
            this.date = date;
            this.menuName = menuName;
            this.eatingStatus = eatingStatus;
            this.difficultyReasons = Collections.unmodifiableList(new ArrayList<>(
                difficultyReasons == null ? Collections.emptyList() : difficultyReasons
            ));
            this.allergyCodes = Collections.unmodifiableSet(new HashSet<>(
                allergyCodes == null ? Collections.emptySet() : allergyCodes
            ));
            this.gainedExp = Math.max(0, gainedExp);
            this.nutrients = Collections.unmodifiableList(new ArrayList<>(
                nutrients == null ? Collections.emptyList() : nutrients
            ));
            this.createdAt = createdAt;
        }

        String mealKey() {
            return date + "|" + normalize(menuName);
        }

        String actionKey() {
            return actionKey(date, menuName, eatingStatus);
        }

        static String actionKey(String date, String menuName, String eatingStatus) {
            return date + "|" + normalize(menuName) + "|" + eatingStatus;
        }

        private static String normalize(String value) {
            return value == null ? "" : value.trim().toLowerCase(java.util.Locale.ROOT);
        }
    }
}
