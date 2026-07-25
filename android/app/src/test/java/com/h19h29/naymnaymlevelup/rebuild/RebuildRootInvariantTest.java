package com.h19h29.naymnaymlevelup.rebuild;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import com.github.javaparser.StaticJavaParser;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.Node;
import com.github.javaparser.ast.body.ClassOrInterfaceDeclaration;
import com.github.javaparser.ast.body.MethodDeclaration;
import com.github.javaparser.ast.expr.ClassExpr;
import com.github.javaparser.ast.expr.FieldAccessExpr;
import com.github.javaparser.ast.expr.MethodCallExpr;
import com.github.javaparser.ast.expr.NameExpr;
import com.github.javaparser.ast.expr.ObjectCreationExpr;
import com.github.javaparser.ast.stmt.BlockStmt;
import com.github.javaparser.ast.stmt.IfStmt;
import com.github.javaparser.ast.stmt.Statement;
import com.h19h29.naymnaymlevelup.BuildConfig;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.List;
import javax.xml.parsers.DocumentBuilderFactory;
import org.junit.Test;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

public final class RebuildRootInvariantTest {
    private static final String ANDROID_NAMESPACE =
            "http://schemas.android.com/apk/res/android";

    @Test
    public void generatedBuildConfigKeepsTheRebuildDisabledByDefault() {
        assertFalse(BuildConfig.NATIVE_REBUILD_ENABLED);
    }

    @Test
    public void manifestKeepsLegacyLauncherAndMakesRebuildActivityPrivate() throws Exception {
        File manifestFile = new File(
                requireSystemProperty("rebuild.mergedManifest"));
        assertTrue(
                "Merged manifest must exist at " + manifestFile.getPath(),
                manifestFile.isFile());

        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document document = factory.newDocumentBuilder().parse(manifestFile);
        NodeList activities = document.getElementsByTagName("activity");
        Element rebuildActivity = findActivity(
                activities,
                "com.h19h29.naymnaymlevelup.rebuild.RebuildActivity");
        Element mainActivity = findActivity(
                activities,
                "com.h19h29.naymnaymlevelup.MainActivity");

        assertNotNull(rebuildActivity);
        assertNotNull(mainActivity);
        assertFalse(Boolean.parseBoolean(
                rebuildActivity.getAttributeNS(ANDROID_NAMESPACE, "exported")));
        assertTrue(Boolean.parseBoolean(
                mainActivity.getAttributeNS(ANDROID_NAMESPACE, "exported")));
        assertTrue(hasMainActionAndLauncherCategory(mainActivity));
    }

    @Test
    public void mainActivityAstUsesOnlyTheCompiledFlagForACompleteRebuildHandoff()
            throws Exception {
        File sourceFile = new File(
                requireSystemProperty("rebuild.mainActivitySource"));
        assertTrue(
                "MainActivity source must exist at " + sourceFile.getPath(),
                sourceFile.isFile());

        CompilationUnit unit = StaticJavaParser.parse(sourceFile);
        assertTrue(hasCompiledFlagRebuildHandoff(unit));
    }

    @Test
    public void lifecycleVerifierRejectsLegacyWorkBeforeTheRebuildGuard() {
        CompilationUnit unit = StaticJavaParser.parse(
                """
                class MainActivity {
                    void onCreate(Object savedInstanceState) {
                        super.onCreate(savedInstanceState);
                        renderHome();
                        if (BuildConfig.NATIVE_REBUILD_ENABLED) {
                            startActivity(new Intent(this, RebuildActivity.class));
                            finish();
                            return;
                        }
                    }
                }
                """);

        assertFalse(hasCompiledFlagRebuildHandoff(unit));
    }

    @Test
    public void manifestVerifierRejectsMainAndLauncherInSeparateIntentFilters()
            throws Exception {
        String manifest =
                """
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    <application>
                        <activity
                            android:name="com.h19h29.naymnaymlevelup.MainActivity"
                            android:exported="true">
                            <intent-filter>
                                <action android:name="android.intent.action.MAIN" />
                            </intent-filter>
                            <intent-filter>
                                <category android:name="android.intent.category.LAUNCHER" />
                            </intent-filter>
                        </activity>
                    </application>
                </manifest>
                """;
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document document = factory
                .newDocumentBuilder()
                .parse(new ByteArrayInputStream(
                        manifest.getBytes(StandardCharsets.UTF_8)));
        Element mainActivity = findActivity(
                document.getElementsByTagName("activity"),
                "com.h19h29.naymnaymlevelup.MainActivity");

        assertNotNull(mainActivity);
        assertFalse(hasMainActionAndLauncherCategory(mainActivity));
    }

    private static Element findActivity(NodeList activities, String className) {
        for (int index = 0; index < activities.getLength(); index++) {
            Element activity = (Element) activities.item(index);
            if (className.equals(
                    activity.getAttributeNS(ANDROID_NAMESPACE, "name"))) {
                return activity;
            }
        }
        return null;
    }

    private static boolean hasIntentFilterValue(
            Element activity,
            String tagName,
            String expected) {
        NodeList nodes = activity.getElementsByTagName(tagName);
        for (int index = 0; index < nodes.getLength(); index++) {
            Element element = (Element) nodes.item(index);
            if (expected.equals(
                    element.getAttributeNS(ANDROID_NAMESPACE, "name"))) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasMainActionAndLauncherCategory(Element activity) {
        NodeList intentFilters = activity.getElementsByTagName("intent-filter");
        for (int index = 0; index < intentFilters.getLength(); index++) {
            Element intentFilter = (Element) intentFilters.item(index);
            if (hasIntentFilterValue(
                    intentFilter,
                    "action",
                    "android.intent.action.MAIN")
                    && hasIntentFilterValue(
                    intentFilter,
                    "category",
                    "android.intent.category.LAUNCHER")) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasCompiledFlagRebuildHandoff(CompilationUnit unit) {
        ClassOrInterfaceDeclaration mainActivity = unit
                .getClassByName("MainActivity")
                .orElseThrow();
        MethodDeclaration onCreate = mainActivity
                .getMethodsByName("onCreate")
                .stream()
                .filter(method -> method.getParameters().size() == 1)
                .findFirst()
                .orElseThrow();
        BlockStmt onCreateBody = onCreate.getBody().orElseThrow();
        List<Statement> statements = onCreateBody.getStatements();
        if (statements.size() < 2
                || !isSuperOnCreate(statements.get(0))
                || !statements.get(1).isIfStmt()
                || !isNativeRebuildFlag(statements.get(1).asIfStmt())) {
            return false;
        }
        List<IfStmt> rebuildGuards = onCreateBody
                .findAll(IfStmt.class)
                .stream()
                .filter(RebuildRootInvariantTest::isNativeRebuildFlag)
                .toList();
        if (rebuildGuards.size() != 1) {
            return false;
        }
        IfStmt rebuildGuard = statements.get(1).asIfStmt();
        return rebuildGuard.getElseStmt().isEmpty()
                && isCompleteRebuildHandoff(rebuildGuard.getThenStmt());
    }

    private static boolean isSuperOnCreate(Statement statement) {
        if (!statement.isExpressionStmt()
                || !statement
                .asExpressionStmt()
                .getExpression()
                .isMethodCallExpr()) {
            return false;
        }
        MethodCallExpr call = statement
                .asExpressionStmt()
                .getExpression()
                .asMethodCallExpr();
        return call.getNameAsString().equals("onCreate")
                && call.getScope().filter(scope -> scope.isSuperExpr()).isPresent()
                && call.getArguments().size() == 1;
    }

    private static boolean isNativeRebuildFlag(IfStmt statement) {
        if (!(statement.getCondition() instanceof FieldAccessExpr)) {
            return false;
        }
        FieldAccessExpr flag = statement
                .getCondition()
                .asFieldAccessExpr();
        return flag.getNameAsString().equals("NATIVE_REBUILD_ENABLED")
                && flag.getScope() instanceof NameExpr
                && flag.getScope()
                .asNameExpr()
                .getNameAsString()
                .equals("BuildConfig");
    }

    private static boolean isCompleteRebuildHandoff(Statement statement) {
        if (!(statement instanceof BlockStmt)) {
            return false;
        }
        List<Statement> statements = statement
                .asBlockStmt()
                .getStatements();
        if (statements.size() != 3
                || !statements.get(0).isExpressionStmt()
                || !statements.get(1).isExpressionStmt()
                || !statements.get(2).isReturnStmt()) {
            return false;
        }

        Node firstExpression = statements
                .get(0)
                .asExpressionStmt()
                .getExpression();
        if (!(firstExpression instanceof MethodCallExpr)) {
            return false;
        }
        MethodCallExpr startActivity = (MethodCallExpr) firstExpression;
        if (!startActivity.getNameAsString().equals("startActivity")
                || startActivity.getArguments().size() != 1
                || !startActivity.getArgument(0).isObjectCreationExpr()) {
            return false;
        }
        ObjectCreationExpr intent = startActivity
                .getArgument(0)
                .asObjectCreationExpr();
        if (!intent.getTypeAsString().equals("Intent")
                || intent.getArguments().size() != 2
                || !(intent.getArgument(1) instanceof ClassExpr)
                || !intent
                .getArgument(1)
                .asClassExpr()
                .getTypeAsString()
                .equals("RebuildActivity")) {
            return false;
        }

        Node secondExpression = statements
                .get(1)
                .asExpressionStmt()
                .getExpression();
        if (!(secondExpression instanceof MethodCallExpr)) {
            return false;
        }
        MethodCallExpr finish = (MethodCallExpr) secondExpression;
        return finish.getNameAsString().equals("finish")
                && finish.getArguments().isEmpty();
    }

    private static String requireSystemProperty(String name) {
        return java.util.Objects.requireNonNull(System.getProperty(name), name);
    }
}
