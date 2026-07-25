# 냠냠레벨업 네이티브 전면 재구축 로드맵 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this roadmap plan-by-plan. Every child plan uses checkbox (`- [ ]`) syntax for task tracking.

**Goal:** 기존 출시 앱을 유지하면서 SwiftUI와 Kotlin Compose 기반의 새 냠냠레벨업을 구축하고, 기록 이전과 베타 검증을 통과한 뒤 같은 앱 식별자로 교체한다.

**Architecture:** 새 구현은 기존 화면 뒤의 비활성 기능 플래그에서 시작한다. iOS는 SwiftUI·Core Data, Android는 Kotlin Compose·Room을 사용하며, 플랫폼 중립 계약과 고정 테스트 벡터로 데이터 의미와 정책을 맞춘다.

**Tech Stack:** Swift 5, SwiftUI, Core Data, XCTest, Kotlin 2.2.21, Jetpack Compose, Room 2.8.4, JUnit, Deno/Supabase Edge Functions, PostgreSQL

## Global Constraints

- iOS 최소 버전은 16.0을 유지한다.
- Android `minSdk 23`, `targetSdk 36`, `compileSdk 36`을 유지한다.
- iOS Bundle ID와 Android applicationId는 모두 `com.h19h29.naymnaymlevelup`을 유지한다.
- 새 구현 기능 플래그는 최종 전환 계획 전까지 기본값 `false`다.
- 광고 SDK와 행동 추적 SDK를 추가하지 않는다.
- 기존 UserDefaults, SharedPreferences, CloudKit 원본 데이터는 검증된 이전 성공 전까지 삭제하지 않는다.
- 스토어 업로드와 배포는 별도 사용자 승인 없이는 수행하지 않는다.

---

## 계획 분할과 실행 순서

### 1. 기반·저장·기록 이전

문서: `docs/superpowers/plans/2026-07-25-native-rebuild-foundation-implementation.md`

완료 시점의 독립 산출물:

- 플랫폼 중립 도메인 계약과 검증 스크립트
- 비활성 상태의 iOS 새 루트와 Android Compose 새 루트
- iOS Core Data 및 Android Room 기본 저장소
- 기존 UserDefaults·SharedPreferences 기록을 원본 보존 상태로 이전하는 코디네이터

### 2. 아이 급식 핵심 순환

문서: `docs/superpowers/plans/2026-07-25-child-meal-loop-implementation.md`

완료 시점의 독립 산출물:

- 캐시 가능한 급식 조회
- 신규 사용자 역할·프로필·학교·알레르기 온보딩
- 메뉴별 식사 기록과 중복 없는 XP 원장
- `오늘 · 성장 · 도감` 내비게이션 중 `오늘`의 완성된 흐름
- 오프라인·급식 없음·알레르기 상태 검증

### 3. 캐릭터·성장·도감

문서: `docs/superpowers/plans/2026-07-25-mascot-growth-motion-implementation.md`

완료 시점의 독립 산출물:

- 원형 유지형 7단계 캐릭터의 공통 캔버스와 파츠 규칙
- 대기·터치·완료·레벨업·위로·동작 축소 상태
- 성장 화면과 도감
- 인트로 로고의 `냠냠 → 레벨업 → 빛` 시퀀스

### 4. 부모 리포트·연결·동기화

문서: `docs/superpowers/plans/2026-07-25-parent-report-sync-implementation.md`

완료 시점의 독립 산출물:

- 공통 서버 v2 계약과 하위 호환
- 오프라인 동기화 대기열과 멱등 업로드
- `요약 · 기록 · 설정` 부모 경험
- CloudKit 연결의 안전한 재연결 처리와 데이터 삭제 흐름

### 5. 접근성·동등성·출시 준비

문서: `docs/superpowers/plans/2026-07-25-native-rebuild-release-readiness-implementation.md`

완료 시점의 독립 산출물:

- 기존 기능 대조표와 양 플랫폼 계약·화면 비교
- Dynamic Type, VoiceOver, 글꼴 확대, TalkBack, 움직임 축소 검증
- 기록 이전·오프라인·충돌·성능 회귀 게이트
- 내부 기능 플래그 전환과 베타 후보 빌드
- 베타 승인 뒤 레거시 iOS/Android 런타임 제거

## 단계 사이의 승인 게이트

각 계획은 다음 조건을 모두 충족한 뒤 다음 계획으로 넘어간다.

1. 계획에 명시된 단위·통합 테스트가 통과한다.
2. iOS Simulator와 Android debug 빌드가 성공한다.
3. `git diff --check`가 통과한다.
4. 새 기능 플래그의 기본값이 `false`인 상태에서 기존 앱이 정상 동작한다.
5. 각 계획의 마지막 커밋을 별도 리뷰한다.

## 최종 전환 조건

- 다섯 계획이 모두 완료되어야 한다.
- 실제 이전 버전 데이터 샘플의 마이그레이션 검증이 통과해야 한다.
- 아이와 부모의 핵심 흐름이 양 플랫폼에서 같은 의미를 가져야 한다.
- 충돌, 기록 손실, 글자 잘림, 접근성 차단 이슈가 없어야 한다.
- 기능 플래그 기본값 변경, TestFlight, Google Play 비공개 테스트, 스토어 제출은 각각 별도 승인받는다.
