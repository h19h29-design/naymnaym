package com.h19h29.naymnaymlevelup;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

public class MealFeedbackPolicyTest {
    @Test
    public void safeBatchSkipsAllergyRiskMenus() {
        List<MealFeedbackPolicy.MenuFeedbackItem> items = Arrays.asList(
            new MealFeedbackPolicy.MenuFeedbackItem("현미밥", Collections.emptySet()),
            new MealFeedbackPolicy.MenuFeedbackItem("우유", Collections.singleton(1))
        );

        MealFeedbackPolicy.BatchSelection result = MealFeedbackPolicy.safeBatch(
            items,
            Collections.singleton(1)
        );

        assertEquals(Collections.singletonList("현미밥"), result.recordedNames);
        assertEquals(Collections.singletonList("우유"), result.skippedNames);
    }

    @Test
    public void safeBatchTreatsMarkedMenusAsWarningsWithoutASelectedProfileAllergy() {
        List<MealFeedbackPolicy.MenuFeedbackItem> items = Arrays.asList(
            new MealFeedbackPolicy.MenuFeedbackItem("현미밥", Collections.emptySet()),
            new MealFeedbackPolicy.MenuFeedbackItem("우유", Collections.singleton(1))
        );

        MealFeedbackPolicy.BatchSelection result = MealFeedbackPolicy.safeBatch(items, Collections.emptySet());

        assertEquals(Collections.singletonList("현미밥"), result.recordedNames);
        assertEquals(Collections.singletonList("우유"), result.skippedNames);
    }

    @Test
    public void connectedCountsStayTruthfulForEachRole() {
        assertEquals(0, MealFeedbackPolicy.childConnectedCount(false));
        assertEquals(1, MealFeedbackPolicy.childConnectedCount(true));
        assertEquals(3, MealFeedbackPolicy.parentConnectedCount(3));
        assertEquals(0, MealFeedbackPolicy.parentConnectedCount(-1));
    }

    @Test
    public void parsesAllergyCodeBeforeASecondNonAllergyParenthetical() {
        assertEquals(
            Collections.singleton(2),
            MealFeedbackPolicy.parseAllergyCodes("우유(2)(125ml)")
        );
    }

    @Test
    public void normalizesLegacyDashedDatesForIosParentSummaries() {
        assertEquals("20260713", MealFeedbackPolicy.normalizeSharedDate("2026-07-13"));
        assertEquals("20260713", MealFeedbackPolicy.normalizeSharedDate("20260713"));
    }

    @Test
    public void snapshotRetryRequiresARegisteredLinkAndPendingLocalData() {
        assertTrue(MealFeedbackPolicy.shouldAttemptSnapshotUpload(true, true, 1));
        assertTrue(MealFeedbackPolicy.shouldAttemptSnapshotUpload(true, true, 0));
        assertFalse(MealFeedbackPolicy.shouldAttemptSnapshotUpload(false, true, 1));
        assertFalse(MealFeedbackPolicy.shouldAttemptSnapshotUpload(true, false, 1));
        assertFalse(MealFeedbackPolicy.shouldAttemptSnapshotUpload(true, false, 0));
        assertTrue(MealFeedbackPolicy.needsInitialSnapshotUpload(false, 1));
        assertFalse(MealFeedbackPolicy.needsInitialSnapshotUpload(true, 1));
        assertFalse(MealFeedbackPolicy.needsInitialSnapshotUpload(false, 0));
    }

    @Test
    public void olderSnapshotSuccessCannotClearNewerPendingWork() {
        assertTrue(MealFeedbackPolicy.shouldClearPendingAfterSuccess(7L, 7L));
        assertFalse(MealFeedbackPolicy.shouldClearPendingAfterSuccess(7L, 8L));
    }

    @Test
    public void snapshotRetryDelayIsBounded() {
        assertEquals(2_000L, MealFeedbackPolicy.snapshotRetryDelayMillis(1));
        assertEquals(4_000L, MealFeedbackPolicy.snapshotRetryDelayMillis(2));
        assertEquals(30_000L, MealFeedbackPolicy.snapshotRetryDelayMillis(20));
    }
}
