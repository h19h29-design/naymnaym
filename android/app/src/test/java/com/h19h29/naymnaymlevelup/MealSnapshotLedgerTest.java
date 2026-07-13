package com.h19h29.naymnaymlevelup;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;

import org.junit.Test;

public class MealSnapshotLedgerTest {
    @Test
    public void completeSnapshotRetainsEveryRecordedMenu() {
        MealSnapshotLedger ledger = new MealSnapshotLedger();

        ledger.record(entry("rice", "2026-07-13", "현미밥", "finished", 10, Collections.emptySet()));
        ledger.record(entry("soup", "2026-07-13", "미역국", "oneBite", 18, Collections.emptySet()));

        assertEquals(2, ledger.latestMeals().size());
        assertEquals(2, ledger.challengeEntries().size());
    }

    @Test
    public void repeatingTheSameActionDoesNotCreateAnotherXpEvent() {
        MealSnapshotLedger ledger = new MealSnapshotLedger();

        assertTrue(ledger.record(entry("first", "2026-07-13", "시금치나물", "oneBite", 18, Collections.emptySet())));
        assertFalse(ledger.record(entry("repeat", "2026-07-13", "시금치나물", "oneBite", 18, Collections.emptySet())));

        assertEquals(1, ledger.challengeEntries().size());
        assertEquals(18, ledger.challengeEntries().get(0).gainedExp);
        assertEquals("repeat-meal", ledger.latestMeals().get(0).mealId);
    }

    @Test
    public void changingStatusKeepsOneLatestMealAndBothGrowthEvents() {
        MealSnapshotLedger ledger = new MealSnapshotLedger();

        ledger.record(entry("difficult", "2026-07-13", "콩나물무침", "difficultToday", 3, Collections.emptySet()));
        ledger.record(entry("bite", "2026-07-13", "콩나물무침", "oneBite", 18, Collections.emptySet()));

        assertEquals(1, ledger.latestMeals().size());
        assertEquals("oneBite", ledger.latestMeals().get(0).eatingStatus);
        assertEquals(2, ledger.challengeEntries().size());
    }

    @Test
    public void latestMealRetainsAllergyCodesForParentSafety() {
        MealSnapshotLedger ledger = new MealSnapshotLedger();

        ledger.record(entry("allergy", "2026-07-13", "우유", "allergyAvoided", 8,
            new java.util.HashSet<>(Arrays.asList(1, 2))));

        assertEquals(new java.util.HashSet<>(Arrays.asList(1, 2)), ledger.latestMeals().get(0).allergyCodes);
    }

    private MealSnapshotLedger.Entry entry(
        String id,
        String date,
        String menu,
        String status,
        int xp,
        java.util.Set<Integer> allergyCodes
    ) {
        return new MealSnapshotLedger.Entry(
            id + "-meal",
            id + "-challenge",
            date,
            menu,
            status,
            Collections.emptyList(),
            allergyCodes,
            xp,
            Collections.emptyList(),
            "2026-07-13T12:00:00Z"
        );
    }
}
