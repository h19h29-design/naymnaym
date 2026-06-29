import SwiftUI

enum MainTab: Hashable {
    case today
    case calendar
    case progress
    case parent
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Binding private var selectedTab: MainTab

    init(selection: Binding<MainTab> = .constant(.today)) {
        _selectedTab = selection
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if appState.currentMode == .parent {
                ParentSummaryView()
                    .tabItem {
                        Label("보호자", systemImage: "person.2.fill")
                    }
                    .tag(MainTab.parent)

                SettingsView()
                    .tabItem {
                        Label("설정", systemImage: "gearshape.fill")
                    }
                    .tag(MainTab.settings)
            } else {
                TodayMealView()
                    .tabItem {
                        Label("오늘급식", systemImage: "house.fill")
                    }
                    .tag(MainTab.today)

                MealCalendarView()
                    .tabItem {
                        Label("식단", systemImage: "calendar")
                    }
                    .tag(MainTab.calendar)

                ProgressAndBadgesView()
                    .tabItem {
                        Label("레벨업", systemImage: "gamecontroller.fill")
                    }
                    .tag(MainTab.progress)

                ParentSummaryView()
                    .tabItem {
                        Label("보호자", systemImage: "person.2.fill")
                    }
                    .tag(MainTab.parent)

                SettingsView()
                    .tabItem {
                        Label("설정", systemImage: "gearshape.fill")
                    }
                    .tag(MainTab.settings)
            }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: appState.currentMode) { _ in
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        if appState.currentMode == .parent, selectedTab != .settings {
            selectedTab = .parent
        }
    }
}
