import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayMealView()
                .tabItem {
                    Label("오늘급식", systemImage: "house.fill")
                }

            MonthlyMealCalendarView()
                .tabItem {
                    Label("월간식단", systemImage: "calendar")
                }

            ProgressAndBadgesView()
                .tabItem {
                    Label("레벨업", systemImage: "gamecontroller.fill")
                }

            ParentSummaryView()
                .tabItem {
                    Label("보호자", systemImage: "person.2.fill")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
    }
}

