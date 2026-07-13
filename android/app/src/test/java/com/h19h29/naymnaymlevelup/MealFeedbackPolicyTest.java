package com.h19h29.naymnaymlevelup;

import static org.junit.Assert.assertEquals;

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
    public void connectedCountsStayTruthfulForEachRole() {
        assertEquals(0, MealFeedbackPolicy.childConnectedCount(false));
        assertEquals(1, MealFeedbackPolicy.childConnectedCount(true));
        assertEquals(3, MealFeedbackPolicy.parentConnectedCount(3));
        assertEquals(0, MealFeedbackPolicy.parentConnectedCount(-1));
    }
}
