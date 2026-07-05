package com.h19h29.naymnaymlevelup;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Html;
import android.util.Log;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int GREEN = Color.rgb(99, 184, 77);
    private static final int DARK_GREEN = Color.rgb(35, 128, 54);
    private static final int ORANGE = Color.rgb(255, 148, 42);
    private static final int CREAM = Color.rgb(255, 249, 232);
    private static final int MINT = Color.rgb(236, 248, 219);
    private static final int TEXT = Color.rgb(45, 38, 30);
    private static final int MUTED = Color.rgb(112, 107, 97);
    private static final int WARNING = Color.rgb(230, 73, 58);
    private static final String PRIVACY_URL = "https://nyam.h19h19.com/privacy.html";
    private static final String SUPPORT_URL = "https://nyam.h19h19.com/support.html";
    private static final String DATA_SAFETY_URL = "https://nyam.h19h19.com/data-safety.html";
    private static final String WEB_INVITE_HOST = "nyam.h19h19.com";
    private static final String WEB_INVITE_BASE = "https://nyam.h19h19.com";
    private static final String LEGACY_WEB_INVITE_HOST = "h19h29-design.github.io";
    private static final String LEGACY_WEB_INVITE_BASE_PATH = "/naymnaym";
    private static final String APP_SCHEME = "nyamnyam";
    private static final String ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;
    private LinearLayout content;
    private TextView statusText;

    private School selectedSchool;
    private boolean demoMode;
    private ChildLink childLink;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("naymnaym-android", MODE_PRIVATE);
        selectedSchool = loadSchool();
        demoMode = prefs.getBoolean("demoMode", false);
        childLink = loadChildLink();
        handleDeepLink(getIntent());
        renderHome();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleDeepLink(intent);
        renderHome();
    }

    private void handleDeepLink(Intent intent) {
        Uri uri = intent == null ? null : intent.getData();
        if (uri == null) return;
        if (isParentInviteUri(uri)) {
            String inviteCode = normalizeInviteCode(uri.getQueryParameter("code"));
            if (isValidInviteCode(inviteCode)) {
                setStatus("초대 링크로 아이 연결을 시작했어요.");
                connectInvite(inviteCode);
            } else {
                setStatus("초대 링크의 코드 형식을 확인해 주세요.");
            }
        } else if (isChildInviteRequestUri(uri)) {
            setStatus("보호자 초대 화면을 열었어요. 링크를 만들고 공유해 주세요.");
            mainHandler.postDelayed(this::renderInvite, 250);
        }
    }

    private boolean isParentInviteUri(Uri uri) {
        String scheme = safeLower(uri.getScheme());
        String host = safeLower(uri.getHost());
        String path = safeLower(uri.getPath());
        if (APP_SCHEME.equals(scheme) || "naymnaym".equals(scheme) || "naymnaymlevelup".equals(scheme)) {
            return "invite".equals(host) || "connect".equals(host) || "connect-child".equals(host) || "parent-connect".equals(host);
        }
        return "https".equals(scheme)
            && ((WEB_INVITE_HOST.equals(host) && path.startsWith("/invite"))
            || (LEGACY_WEB_INVITE_HOST.equals(host) && path.startsWith(LEGACY_WEB_INVITE_BASE_PATH + "/invite")));
    }

    private boolean isChildInviteRequestUri(Uri uri) {
        String scheme = safeLower(uri.getScheme());
        String host = safeLower(uri.getHost());
        String path = safeLower(uri.getPath());
        if (APP_SCHEME.equals(scheme) || "naymnaym".equals(scheme) || "naymnaymlevelup".equals(scheme)) {
            return "parent-invite".equals(host) || "child-invite".equals(host);
        }
        return "https".equals(scheme)
            && ((WEB_INVITE_HOST.equals(host) && (path.startsWith("/parent-invite") || path.startsWith("/child-invite")))
            || (LEGACY_WEB_INVITE_HOST.equals(host) && (path.startsWith(LEGACY_WEB_INVITE_BASE_PATH + "/parent-invite") || path.startsWith(LEGACY_WEB_INVITE_BASE_PATH + "/child-invite"))));
    }

    private String safeLower(String value) {
        return value == null ? "" : value.toLowerCase(Locale.ROOT);
    }

    private void renderHome() {
        ScrollView scrollView = new ScrollView(this);
        scrollView.setFillViewport(false);
        scrollView.setBackgroundColor(CREAM);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(18), dp(18), dp(18), dp(28));
        scrollView.addView(content);
        setContentView(scrollView);

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.logo_naym_levelup);
        logo.setAdjustViewBounds(true);
        content.addView(logo, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(74)));

        TextView subtitle = text("편식을 혼내지 않고, 한 입 도전으로 바꾸는 급식 코칭 앱", 15, TEXT, Typeface.BOLD);
        subtitle.setGravity(Gravity.CENTER);
        content.addView(subtitle);

        ImageView mascot = new ImageView(this);
        mascot.setImageResource(R.drawable.mascot_wave_1);
        mascot.setAdjustViewBounds(true);
        LinearLayout.LayoutParams mascotParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(190));
        mascotParams.setMargins(0, dp(12), 0, dp(6));
        content.addView(mascot, mascotParams);
        mascot.setAlpha(0f);
        mascot.setTranslationY(dp(52));
        mascot.setScaleX(0.92f);
        mascot.setScaleY(0.92f);
        mascot.animate()
            .alpha(1f)
            .translationY(0f)
            .scaleX(1.04f)
            .scaleY(1.04f)
            .setDuration(700)
            .setInterpolator(new AccelerateDecelerateInterpolator())
            .withEndAction(() -> mascot.animate().scaleX(1f).scaleY(1f).rotationBy(-3f).setDuration(260).start())
            .start();

        statusText = text("", 14, MUTED, Typeface.NORMAL);
        statusText.setGravity(Gravity.CENTER);
        statusText.setPadding(dp(8), dp(4), dp(8), dp(10));
        content.addView(statusText);
        setStatus(currentStatusMessage());

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(0, dp(8), 0, dp(4));
        content.addView(actions);
        actions.addView(primaryButton("오늘 급식 보러가기", v -> loadTodayMeal(false)));
        actions.addView(secondaryButton("학교 검색/등록", v -> renderSchoolSearch()));
        actions.addView(secondaryButton("체험 모드", v -> loadTodayMeal(true)));
        actions.addView(secondaryButton("보호자 초대/연결", v -> renderInvite()));
        actions.addView(secondaryButton("개인정보 · 지원 · 데이터 관리", v -> renderPrivacyAndSupport()));

        if (selectedSchool == null) {
            content.addView(card("학교를 등록하면 시작할 수 있어요", "학교를 선택하면 오늘 급식과 한 입 미션을 확인할 수 있어요.", false));
        } else {
            content.addView(card("등록된 학교", selectedSchool.name + "\n" + selectedSchool.region + " / " + selectedSchool.schoolType, false));
        }

        featureCards();
    }

    private String currentStatusMessage() {
        if (BuildConfig.NEIS_API_KEY.trim().isEmpty()) {
            return "NEIS API 키가 없어 실제 급식을 불러올 수 없어요.";
        }
        if (selectedSchool == null) {
            return "학교 등록하고 시작";
        }
        if (demoMode) {
            return "체험 모드예요. 샘플 데이터로 앱을 둘러보는 중이에요.";
        }
        return "오늘도 한 입 도전, 같이 해볼까요?";
    }

    private void featureCards() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(8), 0, 0);
        content.addView(row);
        row.addView(card("한 입 도전", "작은 한 입이 큰 변화를 만들어요.", false));
        row.addView(card("성장 리포트", "점수 비교보다 변화 중심으로 기록해요.", false));
        row.addView(card("응원과 보상", "도전할수록 나도 레벨업!", false));
    }

    private void renderSchoolSearch() {
        resetContent("학교 검색");
        EditText keyword = new EditText(this);
        keyword.setHint("학교 이름을 입력하세요");
        keyword.setSingleLine(true);
        keyword.setInputType(InputType.TYPE_CLASS_TEXT);
        keyword.setTextColor(TEXT);
        keyword.setTextSize(16);
        content.addView(keyword, matchWrap());
        content.addView(primaryButton("검색", v -> searchSchool(keyword.getText().toString().trim())));
        content.addView(secondaryButton("뒤로", v -> renderHome()));
        setStatus("실제 NEIS 학교 검색을 사용합니다. 샘플 학교는 자동 표시하지 않아요.");
    }

    private void searchSchool(String keyword) {
        if (keyword.isEmpty()) {
            setStatus("학교 이름을 입력해 주세요.");
            return;
        }
        if (BuildConfig.NEIS_API_KEY.trim().isEmpty()) {
            setStatus("NEIS API 키가 없어 학교를 검색할 수 없어요.");
            return;
        }
        showLoading("학교를 검색하는 중이에요.");
        executor.execute(() -> {
            try {
                String query = "KEY=" + enc(BuildConfig.NEIS_API_KEY)
                    + "&Type=json&pIndex=1&pSize=20&SCHUL_NM=" + enc(keyword);
                JSONObject json = getJson("https://open.neis.go.kr/hub/schoolInfo?" + query);
                JSONArray rows = json.getJSONArray("schoolInfo").getJSONObject(1).getJSONArray("row");
                List<School> schools = new ArrayList<>();
                for (int i = 0; i < rows.length(); i++) {
                    JSONObject row = rows.getJSONObject(i);
                    schools.add(new School(
                        row.optString("SCHUL_NM"),
                        row.optString("ATPT_OFCDC_SC_CODE"),
                        row.optString("SD_SCHUL_CODE"),
                        row.optString("LCTN_SC_NM"),
                        row.optString("ORG_RDNMA"),
                        row.optString("SCHUL_KND_SC_NM")
                    ));
                }
                mainHandler.post(() -> renderSchoolResults(schools));
            } catch (Exception error) {
                Log.w("NaymAndroid", "School search failed: " + error.getClass().getSimpleName() + ": " + userSafeMessage(error));
                mainHandler.post(() -> {
                    renderSchoolSearch();
                    setStatus("학교 검색에 실패했어요. API 키, 네트워크 상태를 확인해 주세요.");
                });
            }
        });
    }

    private void renderSchoolResults(List<School> schools) {
        resetContent("학교 선택");
        if (schools.isEmpty()) {
            content.addView(card("검색 결과가 없어요", "다른 학교 이름으로 다시 검색해 주세요.", true));
        }
        for (School school : schools) {
            LinearLayout box = cardContainer();
            box.addView(text(school.name, 19, TEXT, Typeface.BOLD));
            box.addView(text(school.region + " · " + school.schoolType + "\n" + school.address, 13, MUTED, Typeface.NORMAL));
            box.addView(primaryButton("이 학교 등록", v -> {
                selectedSchool = school;
                demoMode = false;
                prefs.edit()
                    .putString("schoolName", school.name)
                    .putString("officeCode", school.officeCode)
                    .putString("schoolCode", school.schoolCode)
                    .putString("region", school.region)
                    .putString("address", school.address)
                    .putString("schoolType", school.schoolType)
                    .putBoolean("demoMode", false)
                    .apply();
                renderHome();
                loadTodayMeal(false);
            }));
            content.addView(box);
        }
        content.addView(secondaryButton("다시 검색", v -> renderSchoolSearch()));
        content.addView(secondaryButton("뒤로", v -> renderHome()));
    }

    private void loadTodayMeal(boolean useDemo) {
        demoMode = useDemo;
        prefs.edit().putBoolean("demoMode", demoMode).apply();
        if (useDemo) {
            renderMeal(new MealDay(
                "체험 모드",
                "625 kcal",
                "샘플 데이터",
                new String[]{"현미밥", "미역국", "닭갈비", "콩나물무침", "배추김치"},
                true
            ), "체험 모드예요. 실제 학교 급식이 아니라 샘플 데이터입니다.");
            return;
        }
        if (selectedSchool == null) {
            setStatus("학교를 등록하면 시작할 수 있어요.");
            renderSchoolSearch();
            return;
        }
        if (BuildConfig.NEIS_API_KEY.trim().isEmpty()) {
            setStatus("급식 정보를 불러오지 못했어요. API 키 설정을 확인해 주세요.");
            return;
        }
        showLoading("오늘 급식을 불러오는 중이에요.");
        executor.execute(() -> {
            try {
                String ymd = new SimpleDateFormat("yyyyMMdd", Locale.KOREA).format(new Date());
                String query = "KEY=" + enc(BuildConfig.NEIS_API_KEY)
                    + "&Type=json&pIndex=1&pSize=20"
                    + "&ATPT_OFCDC_SC_CODE=" + enc(selectedSchool.officeCode)
                    + "&SD_SCHUL_CODE=" + enc(selectedSchool.schoolCode)
                    + "&MLSV_YMD=" + ymd;
                JSONObject json = getJson("https://open.neis.go.kr/hub/mealServiceDietInfo?" + query);
                if (!json.has("mealServiceDietInfo")) {
                    if (!"INFO-200".equals(resultCode(json))) {
                        throw new IllegalStateException(resultMessage(json));
                    }
                    mainHandler.post(() -> {
                        renderHome();
                        setStatus("오늘은 급식 정보가 없어요. 방학, 재량휴업일, 급식 미운영일일 수 있어요.");
                    });
                    return;
                }
                JSONArray rows = json.getJSONArray("mealServiceDietInfo").getJSONObject(1).getJSONArray("row");
                if (rows.length() == 0) {
                    mainHandler.post(() -> {
                        renderHome();
                        setStatus("오늘은 급식 정보가 없어요. 샘플 데이터는 표시하지 않아요.");
                    });
                    return;
                }
                JSONObject row = rows.getJSONObject(0);
                String dish = htmlToText(row.optString("DDISH_NM"));
                MealDay meal = new MealDay(
                    selectedSchool.name,
                    row.optString("CAL_INFO"),
                    row.optString("NTR_INFO"),
                    splitMenu(dish),
                    false
                );
                mainHandler.post(() -> renderMeal(meal, "실제 NEIS 급식 조회 성공"));
            } catch (Exception error) {
                Log.w("NaymAndroid", "Meal fetch failed: " + error.getClass().getSimpleName() + ": " + userSafeMessage(error));
                mainHandler.post(() -> {
                    renderHome();
                    setStatus("급식 정보를 불러오지 못했어요. API 키, 학교 설정, 네트워크 상태를 확인해 주세요.");
                });
            }
        });
    }

    private void renderMeal(MealDay meal, String status) {
        resetContent("오늘 급식");
        setStatus(status);
        TextView badge = text(meal.demo ? "체험 모드" : "LIVE", 13, meal.demo ? ORANGE : DARK_GREEN, Typeface.BOLD);
        badge.setGravity(Gravity.CENTER);
        content.addView(badge);
        content.addView(card(meal.schoolName, "칼로리: " + safe(meal.calorie) + "\n영양: " + safe(meal.nutrition), false));
        for (String menu : meal.items) {
            LinearLayout box = cardContainer();
            boolean warning = hasAllergyMarker(menu);
            box.addView(text(cleanMenu(menu), 20, warning ? WARNING : TEXT, Typeface.BOLD));
            box.addView(text(warning ? "알레르기 번호가 있는 메뉴예요. 학교 안내와 보호자 판단이 먼저예요." : "오늘의 한 입 미션 후보", 13, warning ? WARNING : MUTED, Typeface.NORMAL));
            if (warning) {
                box.addView(disabledButton("한 입 도전 잠금"));
                box.addView(secondaryButton("안전하게 확인했어요", v -> recordChallenge(cleanMenu(menu), true)));
            } else {
                box.addView(primaryButton("한 입 도전", v -> recordChallenge(cleanMenu(menu), false)));
            }
            box.addView(secondaryButton("먹은 정도 기록", v -> recordMeal(cleanMenu(menu))));
            content.addView(box);
        }
        content.addView(secondaryButton("보호자 초대/공유", v -> renderInvite()));
        content.addView(secondaryButton("홈", v -> renderHome()));
    }

    private void recordChallenge(String menu, boolean safety) {
        int xp = safety ? 8 : 18;
        setStatus((safety ? "안전 XP" : "도전 XP") + " +" + xp + " · " + menu + " 기록 완료");
        publishSimpleSnapshot(menu, safety ? "allergyAvoided" : "oneBite", xp);
    }

    private void recordMeal(String menu) {
        setStatus("기록 XP +10 · " + menu + " 기록 완료");
        publishSimpleSnapshot(menu, "finished", 10);
    }

    private void renderInvite() {
        resetContent("보호자 초대");
        if (selectedSchool == null && !demoMode) {
            content.addView(card("학교 등록 필요", "부모가 급식 메뉴를 볼 수 있게 하려면 아이 학교를 먼저 등록해 주세요.", true));
            content.addView(primaryButton("학교 등록하기", v -> renderSchoolSearch()));
            content.addView(secondaryButton("뒤로", v -> renderHome()));
            return;
        }
        if (childLink == null) {
            childLink = makeChildLink();
            saveChildLink(childLink);
        }
        content.addView(card("보호자 연결 링크", "코드: " + childLink.inviteCode + "\n링크가 열리지 않으면 이 코드를 붙여넣으면 됩니다.", false));
        content.addView(card("공유 범위", "공유되는 항목은 먹은 정도, 한 입 도전 기록, 알레르기 주의뿐입니다. 급식판 사진, 친구 얼굴, 반/번호, 이름표는 서버나 부모 화면에 올리지 않습니다.", false));
        content.addView(primaryButton("초대 코드 서버 등록", v -> registerInvite()));
        content.addView(primaryButton("공유하기", v -> shareText(parentInviteShareMessage())));
        content.addView(secondaryButton("링크 복사", v -> copyText("초대 링크", parentInviteUrl())));
        content.addView(card("부모에서 아이에게 요청하기", "부모 기기에서 아래 요청 링크를 공유하면 아이 기기에서 이 화면이 열립니다.", false));
        content.addView(secondaryButton("부모 요청 링크 공유", v -> shareText(parentInviteRequestMessage())));
        content.addView(secondaryButton("뒤로", v -> renderHome()));
    }

    private void renderPrivacyAndSupport() {
        resetContent("개인정보와 지원");
        content.addView(card("심사 기준 요약", "회원가입, 광고, 결제, 위치 권한, 연락처 권한을 사용하지 않습니다. 학교 코드와 날짜는 NEIS 급식 조회에만 사용합니다.", false));
        content.addView(card("사진과 부모 공유", "급식판 사진은 Android 테스트 앱에서도 부모에게 공유하지 않습니다. 부모 공유는 초대 코드로 연결한 뒤 먹은 정도, 한 입 도전 기록, 알레르기 주의만 사용합니다.", false));
        content.addView(card("알레르기 안내", "알레르기 정보와 영양 안내는 교육용 참고 정보입니다. 앱은 안전을 보장하지 않으며 학교 안내와 보호자 판단이 항상 우선입니다.", true));
        content.addView(primaryButton("개인정보 처리방침 열기", v -> openUrl(PRIVACY_URL)));
        content.addView(secondaryButton("데이터 안전 안내 열기", v -> openUrl(DATA_SAFETY_URL)));
        content.addView(secondaryButton("지원 안내 열기", v -> openUrl(SUPPORT_URL)));
        content.addView(secondaryButton("데이터 관리", v -> renderDataManagement()));
        content.addView(secondaryButton("홈", v -> renderHome()));
        setStatus("심사용 개인정보, 지원, 삭제 안내를 확인할 수 있어요.");
    }

    private void renderDataManagement() {
        resetContent("데이터 관리");
        content.addView(card("삭제 전 확인", "삭제한 데이터는 되돌릴 수 없습니다. 기기 내부의 학교, 체험 모드, 보호자 초대 코드, 기록 상태가 삭제됩니다.", true));
        content.addView(dangerButton("이 기기의 앱 데이터 삭제", v -> confirmClearLocalData()));
        content.addView(secondaryButton("뒤로", v -> renderPrivacyAndSupport()));
        content.addView(secondaryButton("홈", v -> renderHome()));
    }

    private void confirmClearLocalData() {
        new AlertDialog.Builder(this)
            .setTitle("이 기기의 앱 데이터를 삭제할까요?")
            .setMessage("학교, 체험 모드, 보호자 초대 코드와 로컬 기록 상태가 삭제됩니다. 삭제한 데이터는 되돌릴 수 없습니다.")
            .setNegativeButton("취소", null)
            .setPositiveButton("삭제", (dialog, which) -> clearLocalData())
            .show();
    }

    private void clearLocalData() {
        prefs.edit().clear().apply();
        selectedSchool = null;
        demoMode = false;
        childLink = null;
        renderHome();
        setStatus("이 기기의 앱 데이터를 삭제했어요.");
    }

    private void registerInvite() {
        if (childLink == null) {
            childLink = makeChildLink();
            saveChildLink(childLink);
        }
        showLoading("초대 코드를 서버에 등록하는 중이에요.");
        executor.execute(() -> {
            try {
                JSONObject link = childLinkJson(childLink);
                JSONObject payload = new JSONObject()
                    .put("link", link)
                    .put("inviteSecret", childLink.inviteSecret);
                JSONObject response = postParentSync("registerInvite", payload);
                if (!response.optBoolean("ok")) throw new IllegalStateException(response.optString("error"));
                childLink.registeredAt = new Date().toString();
                saveChildLink(childLink);
                mainHandler.post(() -> {
                    renderInvite();
                    setStatus("등록 완료. 공유하기를 누르면 카카오톡, 메시지, 복사하기가 떠요.");
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    renderInvite();
                    setStatus("초대 코드 등록 실패: " + userSafeMessage(error));
                });
            }
        });
    }

    private void connectInvite(String inviteCode) {
        showLoading("아이 연결 정보를 불러오는 중이에요.");
        executor.execute(() -> {
            try {
                JSONObject payload = new JSONObject().put("inviteCode", inviteCode);
                JSONObject response = postParentSync("connectInvite", payload);
                if (!response.optBoolean("ok")) throw new IllegalStateException(response.optString("error"));
                JSONObject link = response.getJSONObject("data").getJSONObject("link");
                String childName = link.optString("childNickname", "아이");
                String schoolName = link.optString("schoolName", "학교");
                mainHandler.post(() -> {
                    resetContent("보호자 연결 완료");
                    content.addView(card(childName + " 연결 완료", schoolName + "의 공유 기록을 확인할 수 있어요.", false));
                    content.addView(secondaryButton("홈", v -> renderHome()));
                    setStatus("부모 연결 완료");
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    renderHome();
                    setStatus("아이 연결 실패: " + userSafeMessage(error));
                });
            }
        });
    }

    private void publishSimpleSnapshot(String menu, String status, int gainedExp) {
        if (childLink == null || childLink.inviteSecret == null || childLink.inviteSecret.isEmpty()) {
            return;
        }
        executor.execute(() -> {
            try {
                String now = isoNow();
                JSONArray mealRecords = new JSONArray()
                    .put(new JSONObject()
                        .put("id", UUID.randomUUID().toString())
                        .put("date", new SimpleDateFormat("yyyy-MM-dd", Locale.KOREA).format(new Date()))
                        .put("menuName", menu)
                        .put("eatingStatus", status)
                        .put("difficultyReasons", new JSONArray())
                        .put("allergyCodes", new JSONArray())
                        .put("photoIds", new JSONArray())
                        .put("createdAt", now));
                JSONArray challenges = new JSONArray()
                    .put(new JSONObject()
                        .put("id", UUID.randomUUID().toString())
                        .put("date", new SimpleDateFormat("yyyy-MM-dd", Locale.KOREA).format(new Date()))
                        .put("menuName", menu)
                        .put("action", status)
                        .put("gainedExp", gainedExp)
                        .put("badgeName", JSONObject.NULL)
                        .put("nutrients", new JSONArray())
                        .put("createdAt", now));
                JSONObject payload = new JSONObject()
                    .put("childLinkId", childLink.id)
                    .put("inviteSecret", childLink.inviteSecret)
                    .put("mealRecords", mealRecords)
                    .put("challengeRecords", challenges);
                postParentSync("publishSnapshot", payload);
            } catch (Exception ignored) {
                // The local record is still valid; parent sync errors are surfaced during explicit invite registration.
            }
        });
    }

    private JSONObject postParentSync(String action, JSONObject payload) throws Exception {
        JSONObject body = new JSONObject().put("action", action).put("payload", payload);
        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
        HttpURLConnection connection = (HttpURLConnection) new URL(BuildConfig.PARENT_SYNC_API_BASE_URL).openConnection();
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json");
        connection.setRequestProperty("Accept", "application/json");
        connection.setDoOutput(true);
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(12000);
        try (OutputStream out = connection.getOutputStream()) {
            out.write(bytes);
        }
        String response = readAll(connection.getResponseCode() >= 400 ? connection.getErrorStream() : connection.getInputStream());
        return new JSONObject(response);
    }

    private JSONObject childLinkJson(ChildLink link) throws Exception {
        JSONObject permissions = new JSONObject()
            .put("shareEatingRecords", true)
            .put("shareChallengeRecords", true)
            .put("shareAllergyWarnings", true)
            .put("sharePhotos", false);
        return new JSONObject()
            .put("id", link.id)
            .put("childNickname", "냠냠 도전자")
            .put("schoolName", selectedSchool == null ? "학교 미설정" : selectedSchool.name)
            .put("officeCode", selectedSchool == null ? "" : selectedSchool.officeCode)
            .put("schoolCode", selectedSchool == null ? "" : selectedSchool.schoolCode)
            .put("regionName", selectedSchool == null ? "" : selectedSchool.region)
            .put("mode", "elementary")
            .put("inviteCode", link.inviteCode)
            .put("permissions", permissions)
            .put("createdAt", isoNow())
            .put("registeredAt", link.registeredAt == null ? JSONObject.NULL : link.registeredAt);
    }

    private void resetContent(String title) {
        ScrollView scrollView = new ScrollView(this);
        scrollView.setBackgroundColor(CREAM);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(18), dp(18), dp(18), dp(28));
        scrollView.addView(content);
        setContentView(scrollView);
        TextView titleView = text(title, 26, TEXT, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        content.addView(titleView);
        statusText = text("", 14, MUTED, Typeface.NORMAL);
        statusText.setGravity(Gravity.CENTER);
        statusText.setPadding(dp(8), dp(8), dp(8), dp(12));
        content.addView(statusText);
    }

    private void showLoading(String message) {
        resetContent("냠냠레벨업");
        setStatus(message);
        ProgressBar progress = new ProgressBar(this);
        content.addView(progress, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)));
    }

    private LinearLayout cardContainer() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(16), dp(14), dp(16), dp(14));
        box.setBackgroundColor(Color.WHITE);
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(10), 0, dp(6));
        box.setLayoutParams(params);
        return box;
    }

    private LinearLayout card(String title, String body, boolean warning) {
        LinearLayout box = cardContainer();
        box.addView(text(title, 18, warning ? WARNING : TEXT, Typeface.BOLD));
        box.addView(text(body, 14, warning ? WARNING : MUTED, Typeface.NORMAL));
        return box;
    }

    private Button primaryButton(String title, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(title);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTextSize(16);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackgroundColor(GREEN);
        button.setOnClickListener(listener);
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, dp(4));
        button.setLayoutParams(params);
        return button;
    }

    private Button dangerButton(String title, View.OnClickListener listener) {
        Button button = primaryButton(title, listener);
        button.setBackgroundColor(WARNING);
        return button;
    }

    private Button secondaryButton(String title, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(title);
        button.setAllCaps(false);
        button.setTextColor(DARK_GREEN);
        button.setTextSize(15);
        button.setBackgroundColor(MINT);
        button.setOnClickListener(listener);
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, dp(4));
        button.setLayoutParams(params);
        return button;
    }

    private Button disabledButton(String title) {
        Button button = secondaryButton(title, null);
        button.setEnabled(false);
        button.setTextColor(MUTED);
        button.setBackgroundColor(Color.rgb(238, 238, 232));
        return button;
    }

    private TextView text(String value, int sp, int color, int style) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setTypeface(Typeface.DEFAULT, style);
        view.setLineSpacing(0, 1.15f);
        view.setPadding(0, dp(4), 0, dp(4));
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private void setStatus(String message) {
        if (statusText != null) {
            statusText.setText(message == null ? "" : message);
        }
    }

    private JSONObject getJson(String url) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(12000);
        connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
        connection.setRequestProperty("Accept-Language", "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7");
        connection.setRequestProperty("Connection", "close");
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) NaymNaymLevelUp/1.0 Mobile Safari/537.36");
        int responseCode = connection.getResponseCode();
        InputStream stream = responseCode >= 400 ? connection.getErrorStream() : connection.getInputStream();
        String body = readAll(stream);
        if (body.isEmpty()) {
            throw new IllegalStateException("서버 응답이 비어 있어요.");
        }
        if (!body.trim().startsWith("{")) {
            if (BuildConfig.DEBUG) {
                String sample = body.replaceAll("\\s+", " ").trim();
                if (sample.length() > 180) sample = sample.substring(0, 180);
                Log.w("NaymAndroid", "Non-JSON NEIS response code=" + responseCode + " body=" + sample);
            }
            throw new IllegalStateException("급식 서버 응답 형식을 확인해 주세요.");
        }
        return new JSONObject(body);
    }

    private String readAll(InputStream input) throws Exception {
        if (input == null) return "";
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
            }
        }
        return builder.toString();
    }

    private String[] splitMenu(String dish) {
        String[] lines = dish.split("\\n");
        List<String> menus = new ArrayList<>();
        for (String line : lines) {
            String trimmed = line.trim();
            if (!trimmed.isEmpty()) menus.add(trimmed);
        }
        return menus.toArray(new String[0]);
    }

    private String cleanMenu(String menu) {
        return menu.replaceAll("\\s*\\([0-9.,\\s]+\\)", "").trim();
    }

    private boolean hasAllergyMarker(String menu) {
        return menu.matches(".*\\([0-9.,\\s]+\\).*");
    }

    private School loadSchool() {
        String name = prefs == null ? "" : prefs.getString("schoolName", "");
        if (name == null || name.isEmpty()) return null;
        return new School(
            name,
            prefs.getString("officeCode", ""),
            prefs.getString("schoolCode", ""),
            prefs.getString("region", ""),
            prefs.getString("address", ""),
            prefs.getString("schoolType", "")
        );
    }

    private ChildLink loadChildLink() {
        String id = prefs.getString("childLinkId", "");
        if (id.isEmpty()) return null;
        ChildLink link = new ChildLink();
        link.id = id;
        link.inviteCode = prefs.getString("inviteCode", "");
        link.inviteSecret = prefs.getString("inviteSecret", "");
        link.registeredAt = prefs.getString("registeredAt", null);
        return link;
    }

    private ChildLink makeChildLink() {
        ChildLink link = new ChildLink();
        link.id = UUID.randomUUID().toString();
        link.inviteCode = makeInviteCode();
        link.inviteSecret = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "");
        return link;
    }

    private void saveChildLink(ChildLink link) {
        prefs.edit()
            .putString("childLinkId", link.id)
            .putString("inviteCode", link.inviteCode)
            .putString("inviteSecret", link.inviteSecret)
            .putString("registeredAt", link.registeredAt)
            .apply();
    }

    private String makeInviteCode() {
        SecureRandom random = new SecureRandom();
        StringBuilder body = new StringBuilder();
        for (int i = 0; i < 12; i++) {
            body.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        return "NYAM-" + body.substring(0, 4) + "-" + body.substring(4, 8) + "-" + body.substring(8, 12);
    }

    private String normalizeInviteCode(String value) {
        if (value == null) return "";
        String compact = value.toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9]", "");
        int index = compact.indexOf("NYAM");
        while (index >= 0 && index + 16 <= compact.length()) {
            String body = compact.substring(index + 4, index + 16);
            if (body.matches("[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}")) {
                return "NYAM-" + body.substring(0, 4) + "-" + body.substring(4, 8) + "-" + body.substring(8, 12);
            }
            index = compact.indexOf("NYAM", index + 4);
        }
        return value.trim().toUpperCase(Locale.ROOT);
    }

    private boolean isValidInviteCode(String code) {
        return code != null && code.matches("^NYAM-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$");
    }

    private String parentInviteUrl() {
        return WEB_INVITE_BASE + "/invite?code=" + (childLink == null ? "" : childLink.inviteCode);
    }

    private String appSchemeParentInviteUrl() {
        return APP_SCHEME + "://invite?code=" + (childLink == null ? "" : childLink.inviteCode);
    }

    private String parentInviteShareMessage() {
        return "냠냠레벨업 보호자 연결 링크\n"
            + parentInviteUrl()
            + "\n\n링크가 열리지 않으면 아래 코드를 부모 모드 > 아이 연결하기에 붙여넣어 주세요.\n"
            + "코드: " + (childLink == null ? "" : childLink.inviteCode)
            + "\n\n앱이 설치되어 있는데 웹 링크가 열리면 아래 주소를 브라우저에 붙여넣어 주세요.\n"
            + appSchemeParentInviteUrl()
            + "\n공유되는 항목은 먹은 정도, 한 입 도전 기록, 알레르기 주의뿐이에요.";
    }

    private String parentInviteRequestMessage() {
        return "냠냠레벨업 보호자 연결을 시작해 주세요.\n"
            + "아이 기기에서 아래 링크를 열면 보호자 초대 화면으로 이동해요.\n"
            + WEB_INVITE_BASE + "/parent-invite"
            + "\n\n링크가 열리지 않으면 아래 주소를 브라우저에 붙여넣어 주세요.\n"
            + APP_SCHEME + "://parent-invite";
    }

    private void shareText(String text) {
        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType("text/plain");
        share.putExtra(Intent.EXTRA_TEXT, text);
        startActivity(Intent.createChooser(share, "공유하기"));
    }

    private void openUrl(String value) {
        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(value)));
    }

    private void copyText(String label, String text) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text));
        setStatus("복사했어요.");
    }

    private String enc(String value) throws Exception {
        return URLEncoder.encode(value == null ? "" : value, "UTF-8");
    }

    @SuppressWarnings("deprecation")
    private String htmlToText(String value) {
        String normalized = (value == null ? "" : value)
            .replace("<br/>", "\n")
            .replace("<br>", "\n");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return Html.fromHtml(normalized, Html.FROM_HTML_MODE_LEGACY).toString();
        }
        return Html.fromHtml(normalized).toString();
    }

    private String isoNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private String safe(String value) {
        return value == null || value.isEmpty() ? "-" : value;
    }

    private String resultCode(JSONObject json) {
        JSONObject result = resultObject(json);
        return result == null ? "" : result.optString("CODE", "");
    }

    private String resultMessage(JSONObject json) {
        JSONObject result = resultObject(json);
        String message = result == null ? "" : result.optString("MESSAGE", "");
        return message.isEmpty() ? "급식 정보를 불러오지 못했어요." : message;
    }

    private JSONObject resultObject(JSONObject json) {
        JSONObject direct = json.optJSONObject("RESULT");
        if (direct != null) return direct;
        JSONArray mealHead = json.optJSONArray("mealServiceDietInfo");
        JSONObject fromMeal = resultFromHead(mealHead);
        if (fromMeal != null) return fromMeal;
        JSONArray schoolHead = json.optJSONArray("schoolInfo");
        return resultFromHead(schoolHead);
    }

    private JSONObject resultFromHead(JSONArray container) {
        if (container == null || container.length() == 0) return null;
        JSONObject first = container.optJSONObject(0);
        if (first == null) return null;
        JSONArray head = first.optJSONArray("head");
        if (head == null) return null;
        for (int i = 0; i < head.length(); i++) {
            JSONObject item = head.optJSONObject(i);
            if (item != null && item.optJSONObject("RESULT") != null) {
                return item.optJSONObject("RESULT");
            }
        }
        return null;
    }

    private String userSafeMessage(Exception error) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? "네트워크 상태를 확인해 주세요." : message;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class School {
        final String name;
        final String officeCode;
        final String schoolCode;
        final String region;
        final String address;
        final String schoolType;

        School(String name, String officeCode, String schoolCode, String region, String address, String schoolType) {
            this.name = name;
            this.officeCode = officeCode;
            this.schoolCode = schoolCode;
            this.region = region;
            this.address = address;
            this.schoolType = schoolType;
        }
    }

    private static final class MealDay {
        final String schoolName;
        final String calorie;
        final String nutrition;
        final String[] items;
        final boolean demo;

        MealDay(String schoolName, String calorie, String nutrition, String[] items, boolean demo) {
            this.schoolName = schoolName;
            this.calorie = calorie;
            this.nutrition = nutrition;
            this.items = items;
            this.demo = demo;
        }
    }

    private static final class ChildLink {
        String id;
        String inviteCode;
        String inviteSecret;
        String registeredAt;
    }
}
