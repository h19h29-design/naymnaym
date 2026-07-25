package com.h19h29.naymnaymlevelup;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
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
import android.view.animation.PathInterpolator;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import com.h19h29.naymnaymlevelup.rebuild.RebuildActivity;
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildLegacyDestinationLauncher;

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
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int GREEN = ReadableColorPalette.GREEN;
    private static final int DARK_GREEN = ReadableColorPalette.DARK_GREEN;
    private static final int ORANGE = ReadableColorPalette.ORANGE;
    private static final int CREAM = ReadableColorPalette.CREAM;
    private static final int MINT = ReadableColorPalette.MINT;
    private static final int TEXT = ReadableColorPalette.TEXT;
    private static final int MUTED = ReadableColorPalette.MUTED;
    private static final int WARNING = ReadableColorPalette.WARNING;
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
    private MealSnapshotLedger mealSnapshotLedger;
    private final List<ParentChildReceipt> parentChildren = new ArrayList<>();
    private SharedPreferences.OnSharedPreferenceChangeListener preferenceListener;
    private boolean refreshingConnectionStatus;
    private final Object snapshotSyncLock = new Object();
    private boolean snapshotUploadInFlight;
    private boolean snapshotRetryScheduled;
    private int snapshotRetryAttempt;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String rebuildDestination = getIntent() == null
            ? null
            : getIntent().getStringExtra(RebuildLegacyDestinationLauncher.EXTRA_ROUTE);
        if (BuildConfig.NATIVE_REBUILD_ENABLED && rebuildDestination == null) {
            startActivity(new Intent(this, RebuildActivity.class));
            finish();
            return;
        }
        prefs = getSharedPreferences("naymnaym-android", MODE_PRIVATE);
        selectedSchool = loadSchool();
        demoMode = prefs.getBoolean("demoMode", false);
        childLink = loadChildLink();
        mealSnapshotLedger = loadMealSnapshotLedger();
        initializeSnapshotSyncState();
        parentChildren.addAll(loadParentChildren());
        preferenceListener = (sharedPreferences, key) -> {
            if (!"parentChildren".equals(key)) return;
            mainHandler.post(this::reloadParentChildren);
        };
        prefs.registerOnSharedPreferenceChangeListener(preferenceListener);
        handleDeepLink(getIntent());
        renderHome();
        if (RebuildLegacyDestinationLauncher.ROUTE_TODAY_MEAL.equals(rebuildDestination)) {
            loadTodayMeal(false);
        } else if (
            RebuildLegacyDestinationLauncher.ROUTE_PARENT_CONNECTION.equals(
                rebuildDestination
            )
        ) {
            renderParentConnections();
        }
        mainHandler.postDelayed(this::retryPendingSnapshotIfNeeded, 600);
    }

    @Override
    protected void onDestroy() {
        if (prefs != null && preferenceListener != null) {
            prefs.unregisterOnSharedPreferenceChangeListener(preferenceListener);
        }
        super.onDestroy();
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
        content.setPadding(
            dp(18),
            dp(ReadableColorPalette.HOME_CONTENT_TOP_INSET_DP),
            dp(18),
            dp(28)
        );
        scrollView.addView(content);
        setContentView(scrollView);

        content.addView(
            createAnimatedIntroLogo(),
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(74))
        );

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

        content.addView(parentConnectionCard());
        if (!parentChildren.isEmpty()) {
            content.addView(parentChildrenConnectionCard());
        }
        refreshChildConnectionStatus(false);

        if (selectedSchool == null) {
            content.addView(card("학교를 등록하면 시작할 수 있어요", "학교를 선택하면 오늘 급식과 한 입 미션을 확인할 수 있어요.", false));
        } else {
            content.addView(card("등록된 학교", selectedSchool.name + "\n" + selectedSchool.region + " / " + selectedSchool.schoolType, false));
        }

        featureCards();
    }

    private View createAnimatedIntroLogo() {
        FrameLayout container = new FrameLayout(this);
        container.setContentDescription("냠냠레벨업");
        container.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);

        ImageView nyamLayer = introLogoImageView();
        ImageView levelUpLayer = introLogoImageView();
        ImageView reducedMotionLayer = introLogoImageView();
        LogoShineView shineLayer = new LogoShineView();

        prepareHiddenWordLayer(nyamLayer);
        prepareHiddenWordLayer(levelUpLayer);
        reducedMotionLayer.setAlpha(0f);
        reducedMotionLayer.setVisibility(View.INVISIBLE);
        shineLayer.setAlpha(0f);

        container.addView(nyamLayer, matchFrame());
        container.addView(levelUpLayer, matchFrame());
        container.addView(reducedMotionLayer, matchFrame());
        container.addView(shineLayer, matchFrame());
        container.post(() -> startIntroLogoMotion(
            container,
            nyamLayer,
            levelUpLayer,
            reducedMotionLayer,
            shineLayer
        ));
        return container;
    }

    private ImageView introLogoImageView() {
        ImageView imageView = new ImageView(this);
        imageView.setImageResource(R.drawable.logo_naym_levelup);
        imageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        imageView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return imageView;
    }

    private FrameLayout.LayoutParams matchFrame() {
        return new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        );
    }

    private void prepareHiddenWordLayer(ImageView layer) {
        layer.setAlpha(0f);
        layer.setTranslationY(dp(Math.round(IntroLogoMotionSpec.INITIAL_Y_DP)));
        layer.setScaleX(IntroLogoMotionSpec.INITIAL_SCALE);
        layer.setScaleY(IntroLogoMotionSpec.INITIAL_SCALE);
    }

    private void startIntroLogoMotion(
        FrameLayout container,
        ImageView nyamLayer,
        ImageView levelUpLayer,
        ImageView reducedMotionLayer,
        LogoShineView shineLayer
    ) {
        if (!container.isAttachedToWindow()) return;

        Drawable logo = nyamLayer.getDrawable();
        if (logo == null || logo.getIntrinsicWidth() <= 0 || logo.getIntrinsicHeight() <= 0) return;

        int viewWidth = container.getWidth();
        int viewHeight = container.getHeight();
        int splitX = IntroLogoMotionSpec.splitX(
            viewWidth,
            viewHeight,
            logo.getIntrinsicWidth(),
            logo.getIntrinsicHeight()
        );
        nyamLayer.setClipBounds(new Rect(0, 0, splitX, viewHeight));
        levelUpLayer.setClipBounds(new Rect(splitX, 0, viewWidth, viewHeight));

        if (!systemAnimationsEnabled()) {
            reducedMotionLayer.setVisibility(View.VISIBLE);
            reducedMotionLayer.animate()
                .alpha(1f)
                .setDuration(IntroLogoMotionSpec.REDUCE_MOTION_FADE_DURATION_MS)
                .start();
            return;
        }

        animateIntroLogoWord(nyamLayer, IntroLogoMotionSpec.NYAM_START_MS);
        animateIntroLogoWord(levelUpLayer, IntroLogoMotionSpec.LEVEL_UP_START_MS);

        shineLayer.setAlpha(0f);
        shineLayer.setProgress(0f);
        ValueAnimator shineAnimator = ValueAnimator.ofFloat(0f, 1f);
        shineAnimator.setStartDelay(IntroLogoMotionSpec.SHINE_START_MS);
        shineAnimator.setDuration(IntroLogoMotionSpec.SHINE_DURATION_MS);
        shineAnimator.setInterpolator(new AccelerateDecelerateInterpolator());
        shineAnimator.addUpdateListener(animation -> {
            if (!container.isAttachedToWindow()) {
                animation.cancel();
                return;
            }
            float progress = (float) animation.getAnimatedValue();
            shineLayer.setProgress(progress);
            float edgeFade = Math.min(1f, Math.min(progress / 0.16f, (1f - progress) / 0.16f));
            shineLayer.setAlpha(0.92f * Math.max(0f, edgeFade));
        });
        shineAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                shineLayer.setAlpha(0f);
            }
        });
        shineAnimator.start();
    }

    private void animateIntroLogoWord(ImageView layer, long startDelayMillis) {
        layer.animate()
            .alpha(1f)
            .translationY(0f)
            .scaleX(1f)
            .scaleY(1f)
            .setStartDelay(startDelayMillis)
            .setDuration(IntroLogoMotionSpec.RISE_DURATION_MS)
            .setInterpolator(new PathInterpolator(0.22f, 0.78f, 0.36f, 1f))
            .start();
    }

    private boolean systemAnimationsEnabled() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled();
    }

    private final class LogoShineView extends View {
        private final Drawable logo;
        private final Paint shinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF logoBounds = new RectF();
        private float progress;

        LogoShineView() {
            super(MainActivity.this);
            logo = getResources().getDrawable(R.drawable.logo_naym_levelup, getTheme()).mutate();
            shinePaint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.SRC_IN));
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        void setProgress(float progress) {
            this.progress = progress;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (getWidth() <= 0 || getHeight() <= 0) return;

            float scale = Math.min(
                (float) getWidth() / logo.getIntrinsicWidth(),
                (float) getHeight() / logo.getIntrinsicHeight()
            );
            float contentWidth = logo.getIntrinsicWidth() * scale;
            float contentHeight = logo.getIntrinsicHeight() * scale;
            float left = (getWidth() - contentWidth) / 2f;
            float top = (getHeight() - contentHeight) / 2f;
            logoBounds.set(left, top, left + contentWidth, top + contentHeight);

            int layer = canvas.saveLayer(logoBounds, null);
            logo.setBounds(
                Math.round(logoBounds.left),
                Math.round(logoBounds.top),
                Math.round(logoBounds.right),
                Math.round(logoBounds.bottom)
            );
            logo.draw(canvas);

            float bandWidth = contentWidth * 0.34f;
            float centerX = logoBounds.left - bandWidth
                + progress * (contentWidth + bandWidth * 2f);
            shinePaint.setShader(new LinearGradient(
                centerX - bandWidth,
                0f,
                centerX + bandWidth,
                0f,
                new int[] {
                    Color.TRANSPARENT,
                    Color.argb(245, 255, 255, 255),
                    Color.argb(195, 255, 245, 173),
                    Color.TRANSPARENT
                },
                new float[] {0f, 0.42f, 0.58f, 1f},
                Shader.TileMode.CLAMP
            ));
            canvas.drawRect(logoBounds, shinePaint);
            canvas.restoreToCount(layer);
        }
    }

    private String currentStatusMessage() {
        if (BuildConfig.NEIS_API_KEY.trim().isEmpty()) {
            return "급식 연동 설정이 필요해요.";
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
            setStatus("급식 연동 설정을 확인해 주세요.");
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
                Log.w("NaymAndroid", "School search failed: " + error.getClass().getSimpleName());
                mainHandler.post(() -> {
                    renderSchoolSearch();
                    setStatus("학교 검색에 실패했어요. 급식 연동 설정과 네트워크 상태를 확인해 주세요.");
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
            box.addView(text(
                school.region + " · " + school.schoolType + "\n" + school.address,
                ReadableColorPalette.MIN_SUPPORTING_TEXT_SP,
                MUTED,
                Typeface.NORMAL
            ));
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
            setStatus("급식 정보를 불러오지 못했어요. 급식 연동 설정을 확인해 주세요.");
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
                Log.w("NaymAndroid", "Meal fetch failed: " + error.getClass().getSimpleName());
                mainHandler.post(() -> {
                    renderHome();
                    setStatus("급식 정보를 불러오지 못했어요. 급식 연동, 학교 설정, 네트워크 상태를 확인해 주세요.");
                });
            }
        });
    }

    private void renderMeal(MealDay meal, String status) {
        resetContent("오늘 급식");
        setStatus(status);
        TextView badge = text(
            meal.demo ? "체험 모드" : "LIVE",
            ReadableColorPalette.MIN_SUPPORTING_TEXT_SP,
            meal.demo ? ORANGE : DARK_GREEN,
            Typeface.BOLD
        );
        badge.setGravity(Gravity.CENTER);
        content.addView(badge);
        content.addView(card(meal.schoolName, "칼로리: " + safe(meal.calorie) + "\n영양: " + safe(meal.nutrition), false));
        content.addView(primaryButton("오늘 급식 다 잘먹었어요", v -> recordAllMeals(meal)));
        for (String menu : meal.items) {
            LinearLayout box = cardContainer();
            boolean warning = hasAllergyMarker(menu);
            box.addView(text(cleanMenu(menu), 20, warning ? WARNING : TEXT, Typeface.BOLD));
            box.addView(text(
                warning ? "알레르기 번호가 있는 메뉴예요. 학교 안내와 보호자 판단이 먼저예요." : nutritionMotivation(cleanMenu(menu)),
                ReadableColorPalette.MIN_SUPPORTING_TEXT_SP,
                warning ? WARNING : MUTED,
                Typeface.NORMAL
            ));
            if (warning) {
                box.addView(disabledButton("한입도전 잠금"));
            } else {
                box.addView(primaryButton("한입도전", v -> recordChallenge(menu, false)));
            }
            box.addView(secondaryButton("잘먹어요", v -> recordMeal(menu)));
            box.addView(secondaryButton("못먹겠어요", v -> showDifficultyDialog(menu, warning)));
            content.addView(box);
        }
        content.addView(secondaryButton("보호자 초대/공유", v -> renderInvite()));
        content.addView(secondaryButton("홈", v -> renderHome()));
    }

    private void recordChallenge(String rawMenu, boolean safety) {
        String menu = cleanMenu(rawMenu);
        FeedbackRecordResult result = recordFeedback(
            rawMenu,
            safety ? "allergyAvoided" : "oneBite",
            Collections.emptyList(),
            safety ? 8 : 18
        );
        if (result.firstAction) {
            setStatus((safety ? "안전 XP" : "도전 XP") + " +" + result.gainedXp + " · " + menu + " 기록 완료");
        } else {
            setStatus(menu + "의 같은 도전은 오늘 이미 기록했어요. XP는 한 번만 받아요.");
        }
        publishCompleteSnapshot();
    }

    private void recordMeal(String rawMenu) {
        String menu = cleanMenu(rawMenu);
        FeedbackRecordResult result = recordFeedback(rawMenu, "finished", Collections.emptyList(), 10);
        if (!result.firstAction) {
            setStatus(menu + "은 오늘 이미 잘먹어요로 기록했어요.");
            publishCompleteSnapshot();
            return;
        }
        markFinishedToday(menu);
        setStatus("기록 XP +" + result.gainedXp + " · " + menu + " 기록 완료");
        publishCompleteSnapshot();
    }

    private void recordAllMeals(MealDay meal) {
        List<MealFeedbackPolicy.MenuFeedbackItem> items = new ArrayList<>();
        for (String raw : meal.items) {
            items.add(new MealFeedbackPolicy.MenuFeedbackItem(cleanMenu(raw), allergyCodes(raw)));
        }
        MealFeedbackPolicy.BatchSelection selection = MealFeedbackPolicy.safeBatch(items, Collections.emptySet());
        int gainedXp = 0;
        Set<String> recordedNames = new HashSet<>(selection.recordedNames);
        for (String rawMenu : meal.items) {
            String menu = cleanMenu(rawMenu);
            if (!recordedNames.contains(menu) || !allergyCodes(rawMenu).isEmpty()) continue;
            FeedbackRecordResult result = recordFeedback(rawMenu, "finished", Collections.emptyList(), 10);
            if (!result.firstAction) continue;
            markFinishedToday(menu);
            gainedXp += result.gainedXp;
        }
        publishCompleteSnapshot();
        showWholeMealPraise(selection, gainedXp);
    }

    private void showWholeMealPraise(MealFeedbackPolicy.BatchSelection selection, int gainedXp) {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(22), dp(10), dp(22), 0);

        ImageView mascot = new ImageView(this);
        mascot.setImageResource(R.drawable.mascot_onboarding);
        mascot.setAdjustViewBounds(true);
        layout.addView(mascot, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(190)));

        String title = selection.skippedNames.isEmpty()
            ? "오늘 급식을 모두 잘 먹었어요!"
            : "주의 메뉴를 제외한 오늘 급식을 잘 먹었어요!";
        TextView titleView = text(title, 21, DARK_GREEN, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        layout.addView(titleView);
        TextView detail = text(
            selection.recordedNames.size() + "개 메뉴 기록 완료"
                + (selection.skippedNames.isEmpty() ? "" : " · 주의 메뉴 " + selection.skippedNames.size() + "개 제외")
                + "\n오늘 받은 XP +" + gainedXp,
            15,
            MUTED,
            Typeface.NORMAL
        );
        detail.setGravity(Gravity.CENTER);
        detail.setPadding(0, dp(8), 0, dp(8));
        layout.addView(detail);

        new AlertDialog.Builder(this)
            .setTitle("오늘의 칭찬")
            .setView(layout)
            .setPositiveButton("칭찬 받기", null)
            .show();
    }

    private void showDifficultyDialog(String rawMenu, boolean allergyRisk) {
        String menu = cleanMenu(rawMenu);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(22), dp(8), dp(22), 0);

        if (allergyRisk) {
            layout.addView(text(
                "안전 확인이 먼저예요\n알레르기/주의 메뉴는 먹지 않아도 괜찮고, 안전하게 피한 기록도 성장으로 인정돼요.",
                15,
                WARNING,
                Typeface.BOLD
            ));
        } else {
            layout.addView(text(
                nutritionMotivation(menu) + "\n\n냄새만 맡아도 도전이에요. 오늘 어렵다고 기록해도 다음 도전의 시작이 됩니다.",
                15,
                TEXT,
                Typeface.NORMAL
            ));
        }

        TextView statusTitle = text("오늘은 어떻게 기록할까요?", 16, TEXT, Typeface.BOLD);
        statusTitle.setPadding(0, dp(14), 0, dp(4));
        layout.addView(statusTitle);

        RadioGroup statusGroup = new RadioGroup(this);
        statusGroup.setOrientation(RadioGroup.VERTICAL);
        List<String> statuses = new ArrayList<>();
        if (allergyRisk) {
            statuses.add("allergyAvoided");
        } else {
            statuses.add("smelledOnly");
            statuses.add("difficultToday");
            if (hasAllergyMarker(rawMenu)) statuses.add("allergyAvoided");
        }
        for (String status : statuses) {
            RadioButton option = new RadioButton(this);
            option.setId(View.generateViewId());
            option.setTag(status);
            option.setText(statusTitle(status));
            option.setTextColor(TEXT);
            option.setTextSize(15);
            statusGroup.addView(option);
            if ((allergyRisk && "allergyAvoided".equals(status)) || (!allergyRisk && "difficultToday".equals(status))) {
                option.setChecked(true);
            }
        }
        layout.addView(statusGroup);

        TextView reasonTitle = text("어떤 점이 어려웠나요?", 16, TEXT, Typeface.BOLD);
        reasonTitle.setPadding(0, dp(12), 0, dp(4));
        layout.addView(reasonTitle);
        String[] reasonLabels = {"맛", "냄새", "식감", "모양", "처음 보는 음식"};
        String[] reasonValues = {"taste", "smell", "texture", "appearance", "unfamiliar"};
        List<CheckBox> reasonChecks = new ArrayList<>();
        for (int i = 0; i < reasonLabels.length; i++) {
            CheckBox reason = new CheckBox(this);
            reason.setText(reasonLabels[i]);
            reason.setTag(reasonValues[i]);
            reason.setTextColor(TEXT);
            reasonChecks.add(reason);
            layout.addView(reason);
        }

        ScrollView dialogScroll = new ScrollView(this);
        dialogScroll.addView(layout);
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
            .setTitle(menu + " · 못먹겠어요")
            .setView(dialogScroll)
            .setNegativeButton("닫기", null)
            .setPositiveButton("이렇게 기록하기", (dialog, which) -> {
                RadioButton selected = statusGroup.findViewById(statusGroup.getCheckedRadioButtonId());
                String status = selected == null ? (allergyRisk ? "allergyAvoided" : "difficultToday") : String.valueOf(selected.getTag());
                List<String> reasons = new ArrayList<>();
                for (CheckBox reason : reasonChecks) {
                    if (reason.isChecked()) reasons.add(String.valueOf(reason.getTag()));
                }
                FeedbackRecordResult result = recordFeedback(rawMenu, status, reasons, requestedXp(status));
                if (result.firstAction) {
                    setStatus(statusTitle(status) + " · " + menu + " · XP +" + result.gainedXp);
                } else {
                    setStatus(menu + "의 같은 기록은 오늘 이미 남겼어요. XP는 한 번만 받아요.");
                }
                publishCompleteSnapshot();
            });
        if (!allergyRisk) {
            builder.setNeutralButton("그래도 한입도전", (dialog, which) -> recordChallenge(rawMenu, false));
        }
        builder.show();
    }

    private String statusTitle(String status) {
        if ("smelledOnly".equals(status)) return "냄새만 맡아봤어요";
        if ("allergyAvoided".equals(status)) return "알레르기·주의로 피했어요";
        return "오늘은 어려워요";
    }

    private int requestedXp(String status) {
        if ("smelledOnly".equals(status)) return 10;
        if ("allergyAvoided".equals(status)) return 8;
        return 3;
    }

    private FeedbackRecordResult recordFeedback(
        String rawMenu,
        String status,
        List<String> reasons,
        int requestedXp
    ) {
        String menu = cleanMenu(rawMenu);
        String date = currentDate();
        boolean firstAction = !mealSnapshotLedger.hasAction(date, menu, status);
        int gainedXp = firstAction ? awardDailyBaseXp(requestedXp) : 0;
        MealSnapshotLedger.Entry entry = new MealSnapshotLedger.Entry(
            UUID.randomUUID().toString(),
            UUID.randomUUID().toString(),
            date,
            menu,
            status,
            reasons,
            allergyCodes(rawMenu),
            gainedXp,
            nutrientTags(menu),
            isoNow()
        );
        boolean recordedAsNew = mealSnapshotLedger.record(entry);
        saveMealSnapshotLedger();
        markSnapshotSyncPending();
        return new FeedbackRecordResult(firstAction && recordedAsNew, gainedXp);
    }

    private List<String> nutrientTags(String menu) {
        String normalized = menu.toLowerCase(Locale.ROOT);
        List<String> tags = new ArrayList<>();
        if (normalized.contains("나물") || normalized.contains("채소") || normalized.contains("김치")) {
            tags.add("식이섬유");
            tags.add("비타민");
        } else if (normalized.contains("고기") || normalized.contains("갈비") || normalized.contains("닭")
            || normalized.contains("두부") || normalized.contains("달걀")) {
            tags.add("단백질");
        } else if (normalized.contains("우유") || normalized.contains("치즈") || normalized.contains("멸치")) {
            tags.add("칼슘");
        } else if (normalized.contains("밥") || normalized.contains("면") || normalized.contains("빵")) {
            tags.add("탄수화물");
        }
        return tags;
    }

    private String currentDate() {
        return new SimpleDateFormat("yyyyMMdd", Locale.KOREA).format(new Date());
    }

    private String nutritionMotivation(String menu) {
        String normalized = menu.toLowerCase(Locale.ROOT);
        if (normalized.contains("나물") || normalized.contains("채소") || normalized.contains("김치")) {
            return "식이섬유와 비타민이 몸의 균형과 활력을 키워줘요.";
        }
        if (normalized.contains("고기") || normalized.contains("갈비") || normalized.contains("닭") || normalized.contains("두부") || normalized.contains("달걀")) {
            return "단백질이 근육과 성장 에너지를 채워줘요.";
        }
        if (normalized.contains("우유") || normalized.contains("치즈") || normalized.contains("멸치")) {
            return "칼슘이 뼈와 치아를 튼튼하게 돕는 메뉴예요.";
        }
        if (normalized.contains("밥") || normalized.contains("면") || normalized.contains("빵")) {
            return "탄수화물이 공부하고 움직일 힘을 채워줘요.";
        }
        return "여러 영양소를 경험하면 오늘의 성장 스탯이 조금씩 올라가요.";
    }

    private Set<Integer> allergyCodes(String menu) {
        return MealFeedbackPolicy.parseAllergyCodes(menu);
    }

    private int awardDailyBaseXp(int requested) {
        String key = "dailyBaseXp-" + todayKey();
        int used = prefs.getInt(key, 0);
        int awarded = Math.max(0, Math.min(requested, 50 - used));
        prefs.edit().putInt(key, used + awarded).apply();
        return awarded;
    }

    private boolean isFinishedToday(String menu) {
        return finishedMealKeys().contains(todayKey() + ":" + normalizedMenuKey(menu));
    }

    private void markFinishedToday(String menu) {
        Set<String> keys = finishedMealKeys();
        keys.add(todayKey() + ":" + normalizedMenuKey(menu));
        prefs.edit().putStringSet("finishedMealKeys", keys).apply();
    }

    private Set<String> finishedMealKeys() {
        return new HashSet<>(prefs.getStringSet("finishedMealKeys", Collections.emptySet()));
    }

    private String normalizedMenuKey(String menu) {
        return cleanMenu(menu).toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }

    private String todayKey() {
        return new SimpleDateFormat("yyyyMMdd", Locale.KOREA).format(new Date());
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
        if (childLink.parentConnectedAt != null && !childLink.parentConnectedAt.isEmpty()) {
            content.addView(connectionSuccessCard("보호자와 연결되었습니다", "연결된 보호자 1명", "급식 결과를 보호자와 함께 확인할 수 있어요."));
            content.addView(secondaryButton("연결 상태 새로고침", v -> refreshChildConnectionStatus(true)));
            content.addView(secondaryButton("뒤로", v -> renderHome()));
            return;
        }
        content.addView(parentConnectionCard());
        boolean inviteReady = childLink.registeredAt != null && !childLink.registeredAt.isEmpty();
        if (inviteReady) {
            content.addView(connectionSuccessCard(
                "초대 링크 준비 완료",
                "보호자 연결 대기 중",
                "부모에게 링크를 보내면 앱에서 바로 연결할 수 있어요."
            ));
        }
        content.addView(card("보호자 연결 링크", "코드: " + childLink.inviteCode + "\n링크가 열리지 않으면 이 코드를 붙여넣으면 됩니다.", false));
        content.addView(card("공유 범위", "공유되는 항목은 먹은 정도, 한 입 도전 기록, 알레르기 주의뿐입니다. 급식판 사진, 친구 얼굴, 반/번호, 이름표는 연결된 보호자 화면에 올리지 않습니다.", false));
        if (inviteReady) {
            content.addView(primaryButton("링크 공유", v -> shareText(parentInviteShareMessage())));
            content.addView(secondaryButton("링크 복사", v -> copyText("초대 링크", parentInviteUrl())));
        } else {
            content.addView(primaryButton("초대 링크 준비하기", v -> registerInvite()));
        }
        content.addView(secondaryButton("연결 상태 새로고침", v -> refreshChildConnectionStatus(true)));
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
        mealSnapshotLedger = new MealSnapshotLedger();
        parentChildren.clear();
        renderHome();
        setStatus("이 기기의 앱 데이터를 삭제했어요.");
    }

    private void registerInvite() {
        if (childLink == null) {
            childLink = makeChildLink();
            saveChildLink(childLink);
        }
        showLoading("초대 링크를 준비하는 중이에요.");
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
                    publishCompleteSnapshot();
                    renderInvite();
                    setStatus("초대 링크 준비 완료. 공유하기를 누르면 카카오톡, 메시지, 복사하기가 떠요.");
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    renderInvite();
                    setStatus("초대 링크를 준비하지 못했어요. 네트워크 상태를 확인해 주세요.");
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
                persistParentChild(new ParentChildReceipt(inviteCode, childName, schoolName));
                mainHandler.post(() -> {
                    reloadParentChildren();
                    resetContent("보호자 연결 완료");
                    content.addView(connectionSuccessCard(
                        childName + "와 연결되었습니다",
                        "연결된 아이 " + MealFeedbackPolicy.parentConnectedCount(parentChildren.size()) + "명",
                        schoolName + "의 공유 기록을 확인할 수 있어요."
                    ));
                    content.addView(secondaryButton("연결된 아이 보기", v -> renderParentConnections()));
                    content.addView(secondaryButton("홈", v -> renderHome()));
                    setStatus("아이와 보호자 연결이 완료됐어요.");
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    renderHome();
                    setStatus("아이 연결에 실패했어요. 초대 코드를 확인하고 다시 시도해 주세요.");
                });
            }
        });
    }

    private LinearLayout parentConnectionCard() {
        if (childLink == null) {
            return card("보호자 연결", "아직 보호자와 연결되지 않았어요", false);
        }
        if (childLink.parentConnectedAt != null && !childLink.parentConnectedAt.isEmpty()) {
            return connectionSuccessCard("보호자와 연결되었습니다", "연결된 보호자 1명", "급식 결과를 보호자와 함께 확인할 수 있어요.");
        }
        if (childLink.registeredAt == null || childLink.registeredAt.isEmpty()) {
            return card("보호자 연결", "아직 보호자와 연결되지 않았어요\n초대 코드를 등록하고 보호자에게 링크를 공유해 주세요.", false);
        }
        return card("보호자 연결 대기 중", "아직 보호자와 연결되지 않았어요\n보호자가 초대 링크를 열면 자동으로 연결됩니다.", false);
    }

    private LinearLayout parentChildrenConnectionCard() {
        LinearLayout card = connectionSuccessCard(
            "아이와 연결되었습니다",
            "연결된 아이 " + MealFeedbackPolicy.parentConnectedCount(parentChildren.size()) + "명",
            "아이의 급식 결과와 도전 변화를 확인할 수 있어요."
        );
        card.setOnClickListener(v -> renderParentConnections());
        return card;
    }

    private void renderParentConnections() {
        resetContent("연결된 아이");
        if (parentChildren.isEmpty()) {
            content.addView(card("아직 연결된 아이가 없어요", "아이에게 초대 요청 링크를 보내거나 받은 초대 링크를 열어 주세요.", false));
            content.addView(primaryButton("아이에게 연결 요청 보내기", v -> shareText(parentInviteRequestMessage())));
        } else {
            content.addView(connectionSuccessCard(
                "아이와 연결되었습니다",
                "연결된 아이 " + MealFeedbackPolicy.parentConnectedCount(parentChildren.size()) + "명",
                "각 아이의 학교와 연결 상태를 확인할 수 있어요."
            ));
            for (ParentChildReceipt child : parentChildren) {
                content.addView(card(child.childName, child.schoolName + "\n연결 완료", false));
            }
        }
        content.addView(secondaryButton("홈", v -> renderHome()));
    }

    private void refreshChildConnectionStatus(boolean showResult) {
        if (refreshingConnectionStatus || childLink == null || childLink.registeredAt == null
            || childLink.inviteSecret == null || childLink.inviteSecret.isEmpty()) {
            if (showResult) setStatus("초대 링크를 먼저 준비해 주세요.");
            return;
        }
        refreshingConnectionStatus = true;
        executor.execute(() -> {
            try {
                JSONObject payload = new JSONObject()
                    .put("childLinkId", childLink.id)
                    .put("inviteSecret", childLink.inviteSecret);
                JSONObject response = postParentSync("checkConnectionStatus", payload);
                if (!response.optBoolean("ok")) throw new IllegalStateException(response.optString("error"));
                String connectedAt = response.getJSONObject("data").optString("connectedAt", "");
                boolean changed = !connectedAt.equals(childLink.parentConnectedAt == null ? "" : childLink.parentConnectedAt);
                childLink.parentConnectedAt = connectedAt.isEmpty() ? null : connectedAt;
                saveChildLink(childLink);
                mainHandler.post(() -> {
                    refreshingConnectionStatus = false;
                    if (changed) {
                        renderHome();
                    }
                    if (showResult) {
                        setStatus(childLink.parentConnectedAt == null
                            ? "아직 보호자와 연결되지 않았어요"
                            : "보호자와 연결되었습니다");
                    }
                });
            } catch (Exception error) {
                mainHandler.post(() -> {
                    refreshingConnectionStatus = false;
                    if (showResult) setStatus("연결 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.");
                });
            }
        });
    }

    private void publishCompleteSnapshot() {
        boolean hasRegisteredLink = childLink != null && childLink.registeredAt != null
            && !childLink.registeredAt.isEmpty() && childLink.inviteSecret != null && !childLink.inviteSecret.isEmpty();
        boolean pending = prefs.getBoolean("snapshotSyncPending", false);
        int recordCount = mealSnapshotLedger.latestMeals().size() + mealSnapshotLedger.challengeEntries().size();
        if (!MealFeedbackPolicy.shouldAttemptSnapshotUpload(hasRegisteredLink, pending, recordCount)) {
            return;
        }
        synchronized (snapshotSyncLock) {
            if (snapshotUploadInFlight) return;
            snapshotUploadInFlight = true;
        }
        final long uploadRevision = prefs.getLong("snapshotSyncRevision", 0L);
        final String childLinkId = childLink.id;
        final String inviteSecret = childLink.inviteSecret;
        final JSONArray mealRecords = new JSONArray();
        final JSONArray challenges = new JSONArray();
        try {
            for (MealSnapshotLedger.Entry entry : mealSnapshotLedger.latestMeals()) {
                mealRecords.put(new JSONObject()
                    .put("id", entry.mealId)
                    .put("date", entry.date)
                    .put("menuName", entry.menuName)
                    .put("eatingStatus", entry.eatingStatus)
                    .put("difficultyReasons", new JSONArray(entry.difficultyReasons))
                    .put("allergyCodes", new JSONArray(entry.allergyCodes))
                    .put("photoIds", new JSONArray())
                    .put("createdAt", entry.createdAt));
            }
            for (MealSnapshotLedger.Entry entry : mealSnapshotLedger.challengeEntries()) {
                challenges.put(new JSONObject()
                    .put("id", entry.challengeId)
                    .put("date", entry.date)
                    .put("menuName", entry.menuName)
                    .put("action", challengeAction(entry.eatingStatus))
                    .put("eatingStatus", entry.eatingStatus)
                    .put("gainedExp", entry.gainedExp)
                    .put("badgeName", JSONObject.NULL)
                    .put("nutrients", new JSONArray(entry.nutrients))
                    .put("createdAt", entry.createdAt));
            }
        } catch (Exception error) {
            Log.w("NaymAndroid", "Could not prepare parent snapshot: " + error.getClass().getSimpleName());
            completeSnapshotUpload(false, uploadRevision);
            return;
        }
        executor.execute(() -> {
            try {
                JSONObject payload = new JSONObject()
                    .put("childLinkId", childLinkId)
                    .put("inviteSecret", inviteSecret)
                    .put("mealRecords", mealRecords)
                    .put("challengeRecords", challenges);
                JSONObject response = postParentSync("publishSnapshot", payload);
                if (!response.optBoolean("ok")) {
                    throw new IllegalStateException("snapshot_rejected");
                }
                completeSnapshotUpload(true, uploadRevision);
            } catch (Exception error) {
                Log.w("NaymAndroid", "Parent snapshot remains pending: " + error.getClass().getSimpleName());
                completeSnapshotUpload(false, uploadRevision);
            }
        });
    }

    private void markSnapshotSyncPending() {
        synchronized (snapshotSyncLock) {
            long nextRevision = prefs.getLong("snapshotSyncRevision", 0L) + 1L;
            prefs.edit()
                .putLong("snapshotSyncRevision", nextRevision)
                .putBoolean("snapshotSyncPending", true)
                .apply();
        }
    }

    private void completeSnapshotUpload(boolean succeeded, long uploadedRevision) {
        boolean stillPending;
        synchronized (snapshotSyncLock) {
            snapshotUploadInFlight = false;
            if (succeeded) {
                long currentRevision = prefs.getLong("snapshotSyncRevision", 0L);
                stillPending = !MealFeedbackPolicy.shouldClearPendingAfterSuccess(
                    uploadedRevision,
                    currentRevision
                );
                prefs.edit().putBoolean("snapshotSyncPending", stillPending).apply();
                snapshotRetryAttempt = 0;
            } else {
                stillPending = true;
                snapshotRetryAttempt += 1;
                prefs.edit().putBoolean("snapshotSyncPending", true).apply();
            }
        }

        if (!stillPending) return;
        if (succeeded) {
            mainHandler.post(this::publishCompleteSnapshot);
        } else {
            scheduleSnapshotRetry();
        }
    }

    private void scheduleSnapshotRetry() {
        final long delayMillis;
        synchronized (snapshotSyncLock) {
            if (snapshotRetryScheduled) return;
            snapshotRetryScheduled = true;
            delayMillis = MealFeedbackPolicy.snapshotRetryDelayMillis(snapshotRetryAttempt);
        }
        mainHandler.postDelayed(() -> {
            synchronized (snapshotSyncLock) {
                snapshotRetryScheduled = false;
            }
            if (!isFinishing()
                && (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1 || !isDestroyed())) {
                publishCompleteSnapshot();
            }
        }, delayMillis);
    }

    private void retryPendingSnapshotIfNeeded() {
        publishCompleteSnapshot();
    }

    private void initializeSnapshotSyncState() {
        boolean initialized = prefs.getBoolean("snapshotSyncInitialized", false);
        int recordCount = mealSnapshotLedger.latestMeals().size() + mealSnapshotLedger.challengeEntries().size();
        boolean needsInitialUpload = MealFeedbackPolicy.needsInitialSnapshotUpload(initialized, recordCount);
        if (!initialized || needsInitialUpload) {
            long revision = prefs.getLong("snapshotSyncRevision", 0L);
            if (needsInitialUpload && revision == 0L) revision = 1L;
            prefs.edit()
                .putBoolean("snapshotSyncInitialized", true)
                .putLong("snapshotSyncRevision", revision)
                .putBoolean("snapshotSyncPending", prefs.getBoolean("snapshotSyncPending", false) || needsInitialUpload)
                .apply();
        }
    }

    private String challengeAction(String status) {
        if ("oneBite".equals(status)) return "oneBite";
        if ("finished".equals(status) || "half".equals(status)) return "alreadyEats";
        return "skipped";
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
            .put("registeredAt", link.registeredAt == null ? JSONObject.NULL : link.registeredAt)
            .put("connectedAt", link.parentConnectedAt == null ? JSONObject.NULL : link.parentConnectedAt);
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

    private LinearLayout connectionSuccessCard(String title, String count, String message) {
        LinearLayout box = cardContainer();
        box.setBackgroundColor(MINT);
        TextView titleView = text("✓ " + title, 20, DARK_GREEN, Typeface.BOLD);
        titleView.setPadding(0, 0, 0, dp(5));
        box.addView(titleView);
        box.addView(text(count, 18, DARK_GREEN, Typeface.BOLD));
        TextView messageView = text(message, 14, MUTED, Typeface.NORMAL);
        messageView.setPadding(0, dp(5), 0, 0);
        box.addView(messageView);
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
        link.parentConnectedAt = prefs.getString("parentConnectedAt", null);
        return link;
    }

    private MealSnapshotLedger loadMealSnapshotLedger() {
        MealSnapshotLedger ledger = new MealSnapshotLedger();
        String stored = prefs.getString("mealSnapshotLedger", "{}");
        try {
            JSONObject root = new JSONObject(stored == null ? "{}" : stored);
            JSONArray latestMeals = root.optJSONArray("latestMeals");
            if (latestMeals != null) {
                for (int index = 0; index < latestMeals.length(); index++) {
                    JSONObject value = latestMeals.optJSONObject(index);
                    if (value != null) ledger.restoreLatest(mealLedgerEntry(value));
                }
            }
            JSONArray actions = root.optJSONArray("actions");
            if (actions != null) {
                for (int index = 0; index < actions.length(); index++) {
                    JSONObject value = actions.optJSONObject(index);
                    if (value != null) ledger.restoreChallenge(mealLedgerEntry(value));
                }
            }
        } catch (Exception ignored) {
            // Corrupt legacy data starts with a clean local sharing ledger.
        }
        return ledger;
    }

    private void saveMealSnapshotLedger() {
        JSONArray latestMeals = new JSONArray();
        JSONArray actions = new JSONArray();
        try {
            for (MealSnapshotLedger.Entry entry : mealSnapshotLedger.latestMeals()) {
                latestMeals.put(mealLedgerJson(entry));
            }
            for (MealSnapshotLedger.Entry entry : mealSnapshotLedger.challengeEntries()) {
                actions.put(mealLedgerJson(entry));
            }
            JSONObject root = new JSONObject()
                .put("latestMeals", latestMeals)
                .put("actions", actions);
            prefs.edit().putString("mealSnapshotLedger", root.toString()).apply();
        } catch (Exception error) {
            Log.w("NaymAndroid", "Could not save meal ledger: " + error.getClass().getSimpleName());
        }
    }

    private JSONObject mealLedgerJson(MealSnapshotLedger.Entry entry) throws Exception {
        return new JSONObject()
            .put("mealId", entry.mealId)
            .put("challengeId", entry.challengeId)
            .put("date", entry.date)
            .put("menuName", entry.menuName)
            .put("eatingStatus", entry.eatingStatus)
            .put("difficultyReasons", new JSONArray(entry.difficultyReasons))
            .put("allergyCodes", new JSONArray(entry.allergyCodes))
            .put("gainedExp", entry.gainedExp)
            .put("nutrients", new JSONArray(entry.nutrients))
            .put("createdAt", entry.createdAt);
    }

    private MealSnapshotLedger.Entry mealLedgerEntry(JSONObject value) {
        return new MealSnapshotLedger.Entry(
            value.optString("mealId", UUID.randomUUID().toString()),
            value.optString("challengeId", UUID.randomUUID().toString()),
            MealFeedbackPolicy.normalizeSharedDate(value.optString("date", currentDate())),
            value.optString("menuName", "메뉴"),
            value.optString("eatingStatus", "difficultToday"),
            stringValues(value.optJSONArray("difficultyReasons")),
            integerValues(value.optJSONArray("allergyCodes")),
            value.optInt("gainedExp", 0),
            stringValues(value.optJSONArray("nutrients")),
            value.optString("createdAt", isoNow())
        );
    }

    private List<String> stringValues(JSONArray values) {
        List<String> result = new ArrayList<>();
        if (values == null) return result;
        for (int index = 0; index < values.length(); index++) {
            String value = values.optString(index, "");
            if (!value.isEmpty()) result.add(value);
        }
        return result;
    }

    private Set<Integer> integerValues(JSONArray values) {
        Set<Integer> result = new HashSet<>();
        if (values == null) return result;
        for (int index = 0; index < values.length(); index++) {
            int value = values.optInt(index, 0);
            if (value > 0) result.add(value);
        }
        return result;
    }

    private List<ParentChildReceipt> loadParentChildren() {
        List<ParentChildReceipt> children = new ArrayList<>();
        String stored = prefs.getString("parentChildren", "[]");
        try {
            JSONArray array = new JSONArray(stored == null ? "[]" : stored);
            for (int i = 0; i < array.length(); i++) {
                JSONObject child = array.optJSONObject(i);
                if (child == null) continue;
                String inviteCode = child.optString("inviteCode", "");
                if (inviteCode.isEmpty()) continue;
                children.add(new ParentChildReceipt(
                    inviteCode,
                    child.optString("childName", "아이"),
                    child.optString("schoolName", "학교")
                ));
            }
        } catch (Exception ignored) {
            // Invalid legacy data is treated as no parent-side connections.
        }
        return children;
    }

    private void persistParentChild(ParentChildReceipt child) {
        List<ParentChildReceipt> storedChildren = loadParentChildren();
        for (int index = storedChildren.size() - 1; index >= 0; index--) {
            if (storedChildren.get(index).inviteCode.equals(child.inviteCode)) {
                storedChildren.remove(index);
            }
        }
        storedChildren.add(0, child);
        JSONArray array = new JSONArray();
        for (ParentChildReceipt receipt : storedChildren) {
            try {
                array.put(new JSONObject()
                    .put("inviteCode", receipt.inviteCode)
                    .put("childName", receipt.childName)
                    .put("schoolName", receipt.schoolName));
            } catch (Exception ignored) {
                // Keep saving the remaining valid receipts.
            }
        }
        prefs.edit().putString("parentChildren", array.toString()).commit();
    }

    private void reloadParentChildren() {
        parentChildren.clear();
        parentChildren.addAll(loadParentChildren());
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
            .putString("parentConnectedAt", link.parentConnectedAt)
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

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class FeedbackRecordResult {
        final boolean firstAction;
        final int gainedXp;

        FeedbackRecordResult(boolean firstAction, int gainedXp) {
            this.firstAction = firstAction;
            this.gainedXp = gainedXp;
        }
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
        String parentConnectedAt;
    }

    private static final class ParentChildReceipt {
        final String inviteCode;
        final String childName;
        final String schoolName;

        ParentChildReceipt(String inviteCode, String childName, String schoolName) {
            this.inviteCode = inviteCode;
            this.childName = childName;
            this.schoolName = schoolName;
        }
    }
}
