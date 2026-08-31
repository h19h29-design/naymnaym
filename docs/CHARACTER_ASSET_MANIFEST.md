# Character Asset Manifest

manifest_version: 1
schema: character-asset-manifest-v1

This manifest is the reviewable record for character visuals used by the
growth, collection, and today forest surfaces. The `MascotRigLevelCatalog`
is the only source of truth for verified art IDs. The repository contains
verified character files for stages 1–7 only. Stages 8–12 retain their
policy-defined names, thresholds, and lock state, but intentionally use a
static native placeholder with the exact visible and accessibility text
`그림 준비 중`; no stage-7 art, medal, crown, or other decoration is used as
their stage art. Source rights have not been independently confirmed here;
this document records provenance and checksums without making a rights claim.

## Stage resolution

| stage_id | stage_name | threshold_xp | resolution | source_path | sha256 | source | license_status | fallback_text |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| 1 | 냠냠 새싹 | 0 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_1.imageset/Squirrel_Growth_Level_1.png | e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa | existing project source | pending independent confirmation | N/A |
| 2 | 한 입 탐험가 | 80 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_2.imageset/Squirrel_Growth_Level_2.png | e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878 | existing project source | pending independent confirmation | N/A |
| 3 | 냠냠 용사 | 180 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_3.imageset/Squirrel_Growth_Level_3.png | 4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5 | existing project source | pending independent confirmation | N/A |
| 4 | 편식 몬스터 사냥꾼 | 320 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_4.imageset/Squirrel_Growth_Level_4.png | a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1 | existing project source | pending independent confirmation | N/A |
| 5 | 급식 히어로 | 500 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_5.imageset/Squirrel_Growth_Level_5.png | 4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2 | existing project source | pending independent confirmation | N/A |
| 6 | 영양 마스터 | 720 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_6.imageset/Squirrel_Growth_Level_6.png | 5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188 | existing project source | pending independent confirmation | N/A |
| 7 | 레전드 냠냠러 | 1000 | verified-in-repository | NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_7.imageset/Squirrel_Growth_Level_7.png | bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb | existing project source | pending independent confirmation | N/A |
| 8 | 별빛 셰프 | 1300 | neutral-fallback | N/A | N/A | native system placeholder | N/A | 그림 준비 중 |
| 9 | 균형 수호자 | 1650 | neutral-fallback | N/A | N/A | native system placeholder | N/A | 그림 준비 중 |
| 10 | 숲의 영양 기사 | 2050 | neutral-fallback | N/A | N/A | native system placeholder | N/A | 그림 준비 중 |
| 11 | 황금 한입 챔피언 | 2500 | neutral-fallback | N/A | N/A | native system placeholder | N/A | 그림 준비 중 |
| 12 | 전설의 급식대장 | 3000 | neutral-fallback | N/A | N/A | native system placeholder | N/A | 그림 준비 중 |

## Verified mascot rig keyframes

These files are the existing first-party rig inputs for stages 1–7. They are
listed so a checksum change is visible during review; no new art is implied.

| stage_id | keyframe | source_path | sha256 | source | license_status |
| --- | --- | --- | --- | --- | --- |
| 1 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_01/composite-rest.png | ab0e53ee0d330490efa9dd4c3eaf3138ec6ef4d44a93079e928cf5a415fa9f60 | existing project source | pending independent confirmation |
| 1 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_01/composite-blink.png | 8f751b950d36776865c026564cb3460eaab0b1fcde3efb71d27f62006f4b9c3e | existing project source | pending independent confirmation |
| 1 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_01/composite-celebrate.png | d22f37412faed68e14eb5fe96a6798846ddc1c90940fa23108b4f53864dbcd95 | existing project source | pending independent confirmation |
| 2 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_02/composite-rest.png | e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878 | existing project source | pending independent confirmation |
| 2 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_02/composite-blink.png | 7dd5b5d5a4f759669a27426b63f9c11c80dd86b7c1f37b63cef2ccff543cfb05 | existing project source | pending independent confirmation |
| 2 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_02/composite-celebrate.png | b15d29cb486e1000ab799af5f019cd4b8660b31b8330f640e7dd2673f308b502 | existing project source | pending independent confirmation |
| 3 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_03/composite-rest.png | 4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5 | existing project source | pending independent confirmation |
| 3 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_03/composite-blink.png | 1f887a111aa37d2d9516e1473f3a0f31ec82b4246344d719e5b38157927da46c | existing project source | pending independent confirmation |
| 3 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_03/composite-celebrate.png | 228bdde37c3b6558f02fbc34c7c41c789691bc4df5e0c4f68c239f386e43f586 | existing project source | pending independent confirmation |
| 4 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_04/composite-rest.png | a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1 | existing project source | pending independent confirmation |
| 4 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_04/composite-blink.png | 1b51c6a4b3c3ce50c342075b0ca70c83ba3e91f42eca02c5d44f80a3671cdebd | existing project source | pending independent confirmation |
| 4 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_04/composite-celebrate.png | abc3f8c6b695a7dedbc68d2b31992fb449b88a2ea2616be4123059190aee516d | existing project source | pending independent confirmation |
| 5 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_05/composite-rest.png | 4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2 | existing project source | pending independent confirmation |
| 5 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_05/composite-blink.png | e78dadf2f4145ce181468e48cfc0146e08abf70c6e1f8d4fb2dae12393a8d387 | existing project source | pending independent confirmation |
| 5 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_05/composite-celebrate.png | 483741d8b7beac6a76fe9b84be054f3de6ac1a5dd7f97aa55be0029b91ab998c | existing project source | pending independent confirmation |
| 6 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_06/composite-rest.png | 5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188 | existing project source | pending independent confirmation |
| 6 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_06/composite-blink.png | a9f451057ffbcb951e5643628fb9a3c773c6e2113f53711e3c8f2fe0ccca56d5 | existing project source | pending independent confirmation |
| 6 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_06/composite-celebrate.png | 2b6e14ed32d11b48097c7c732de81a586ca4d12b260e71c197a4b6c822e95322 | existing project source | pending independent confirmation |
| 7 | composite-rest | NaymNaymLevelUp/Resources/MascotRig/level_07/composite-rest.png | bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb | existing project source | pending independent confirmation |
| 7 | composite-blink | NaymNaymLevelUp/Resources/MascotRig/level_07/composite-blink.png | f33d5dd292fca15a61a8108d58ac86c6b843995b5c44c7ec59cafc742c193f8d | existing project source | pending independent confirmation |
| 7 | composite-celebrate | NaymNaymLevelUp/Resources/MascotRig/level_07/composite-celebrate.png | c8bb0c3e254ff5cdc5a77ca56d84ca6465f7600378692f02c1a6df43422ffa45 | existing project source | pending independent confirmation |

## First-party Lottie resources

These names and files are the existing first-party animation contract. They
are unchanged by this manifest and are separate from the static 8–12
placeholder.

| animation_name | source_path | sha256 | source | license_status |
| --- | --- | --- | --- | --- |
| mascot_intro | NaymNaymLevelUp/Resources/Animations/mascot_intro.json | 785f97252ba465e81f7a8288ddf8ce9944bbe4828980cfc8cd44fa03937abfd5 | existing first-party animation | pending independent confirmation |
| mascot_idle_loop | NaymNaymLevelUp/Resources/Animations/mascot_idle_loop.json | 98012e35436d1759a4e4225be714ea85f3536391f405340be132f840bccc73dd | existing first-party animation | pending independent confirmation |
| mascot_wave | NaymNaymLevelUp/Resources/Animations/mascot_wave.json | 93c529a6a6243c7ffeb7bd8099dd89404db57484b97ae194453c6514b699448c | existing first-party animation | pending independent confirmation |
| mascot_success | NaymNaymLevelUp/Resources/Animations/mascot_success.json | 595d3e66aea23041945d3b8cc0d250de4f7a3819f48c1f58b4fbbdd01aa69ff0 | existing first-party animation | pending independent confirmation |
| mascot_levelup | NaymNaymLevelUp/Resources/Animations/mascot_levelup.json | 9aec1417f61e8c014b26afa8a73b1855eafdb76add55eb2cc9b466440ec2c3ec | existing first-party animation | pending independent confirmation |
| mascot_allergy_warning | NaymNaymLevelUp/Resources/Animations/mascot_allergy_warning.json | 8fb3ad67c160a626214861fe58ddc2719266f81b2167fdc47ce74b2c51286782 | existing first-party animation | pending independent confirmation |
