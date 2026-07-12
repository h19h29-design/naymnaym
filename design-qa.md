# Squirrel Growth Redesign QA

## Sources

- Approved visual reference: `/Users/mac-mini/Downloads/ChatGPT Image 2026년 7월 12일 오후 03_59_08.png`
- Editable Figma board: <https://www.figma.com/design/PzhrBaw0BuAMNTX4BPyfsM>
- Combined comparison board: `build/verification/figma-squirrel-redesign-board-20260712.png`

## Verified Screens

- Intro / iPhone 16: `build/verification/squirrel-intro-iphone16-20260712.jpg`
- Home / iPhone 16: `build/verification/squirrel-home-iphone16-20260712.jpg`
- Character / iPhone 16: `build/verification/squirrel-character-iphone16-20260712.jpg`
- Core / iPhone SE: `build/verification/squirrel-core-iphonese-20260712.jpg`
- Connection states: `build/verification/squirrel-connection-states-20260712.jpg`
- Intro animation: `build/verification/intro-animation-20260712.mp4`

## Visual Audit

- Character quality: seven consistent high-resolution squirrel stages; cream backgrounds removed without clipping the character.
- Intro hierarchy: logo, current-level squirrel, state-aware mission, primary action, and secondary modes are readable in the first viewport.
- Home hierarchy: current squirrel, level, progress, streak, challenge count, mission, and truthful parent connection state precede meal details.
- Character hierarchy: current level, seven-stage evolution, functional tabs, current character, next reward, badges, XP, and history remain accessible.
- Small screen: iPhone SE build and runtime verification passed; no overlapping controls or clipped primary text.
- Accessibility: accessibility XXXL layouts were verified during Task 5 and Task 6 review.
- Connection copy: child connected state is `보호자와 연결되었습니다`; parent connected state uses `{아이 이름}와 연결되었습니다`.
- Data safety: existing live/demo/no-meal/error separation and allergy one-bite lock remain unchanged.

## Verification

- Full simulator suite: 109 passed, 0 failed.
- iPhone 16 simulator build/run: passed.
- iPhone SE simulator build/run: passed.
- `git diff --check`: passed.

final result: passed
