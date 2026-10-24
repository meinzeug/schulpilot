package de.dorfspy.schulpilot

import java.io.DataInputStream
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

/** Resource contracts for the opaque native-to-Flutter startup handoff. */
class LaunchThemeTest {
    private val android = "http://schemas.android.com/apk/res/android"
    private val res: File
        get() = listOf(
            File("src/main/res"),
            File("app/src/main/res"),
            File("app/android/app/src/main/res"),
        ).firstOrNull { it.resolve("values/styles.xml").isFile }
            ?: error("Android resource directory not found from ${System.getProperty("user.dir")}")

    private fun xml(file: File): Element = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
    }.newDocumentBuilder().parse(file).documentElement

    private fun style(variant: String, name: String): Element {
        val nodes = xml(res.resolve("$variant/styles.xml")).getElementsByTagName("style")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .single { it.getAttribute("name") == name }
    }

    private fun item(style: Element, name: String): String? {
        val nodes = style.getElementsByTagName("item")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .singleOrNull { it.getAttribute("name") == name }?.textContent?.trim()
    }

    @Test fun lightAndDarkWindowThemesShareAnOpaqueStartupAndDecorColor() {
        for (variant in listOf("values", "values-night")) {
            val window = style(variant, "SchulpilotWindowTheme")
            for (attribute in listOf("windowBackground", "statusBarColor", "navigationBarColor")) {
                assertEquals("$variant $attribute",
                    "@color/schulpilot_splash_background", item(window, "android:$attribute"))
            }
            assertEquals("false", item(window, "android:windowLightStatusBar"))
            assertEquals("false", item(window, "android:windowLightNavigationBar"))
            assertEquals("@style/SchulpilotWindowTheme",
                style(variant, "NormalTheme").getAttribute("parent"))
            assertEquals("@style/SchulpilotWindowTheme",
                style(variant, "LaunchTheme").getAttribute("parent"))
        }
        val colors = xml(res.resolve("values/brand.xml")).getElementsByTagName("color")
        val splash = (0 until colors.length).map { colors.item(it) as Element }
            .single { it.getAttribute("name") == "schulpilot_splash_background" }
        assertEquals("#101E24", splash.textContent.trim().uppercase())
    }

    @Test fun legacyLaunchSurfacePaintsTheOpaqueBackgroundBeforeItsLogo() {
        for (variant in listOf("drawable", "drawable-v21")) {
            val layers = xml(res.resolve("$variant/launch_background.xml"))
                .getElementsByTagName("item")
            assertTrue(layers.length >= 2)
            assertEquals("@color/schulpilot_splash_background",
                (layers.item(0) as Element).getAttributeNS(android, "drawable"))
            assertEquals("@drawable/schulpilot_logo",
                (layers.item(layers.length - 1) as Element).getAttributeNS(android, "drawable"))
        }
    }

    @Test fun android12HasExplicitDayAndNightEntriesWithTheSameStaticSplash() {
        val splash = style("values-v31", "SchulpilotSplashTheme")
        assertEquals("@style/SchulpilotWindowTheme", splash.getAttribute("parent"))
        assertEquals("@color/schulpilot_splash_background",
            item(splash, "android:windowSplashScreenBackground"))
        assertEquals("@drawable/schulpilot_splash_logo",
            item(splash, "android:windowSplashScreenAnimatedIcon"))
        for (variant in listOf("values-v31", "values-night-v31")) {
            assertEquals("@style/SchulpilotSplashTheme",
                style(variant, "LaunchTheme").getAttribute("parent"))
        }
        // Animation and wordmark placement belong to Flutter, not a second timed activity.
        assertNull(item(splash, "android:windowSplashScreenAnimationDuration"))
        assertNull(item(splash, "android:windowSplashScreenBrandingImage"))
    }

    @Test fun android13KeepsTheExplicitIconInBothSystemModes() {
        for (variant in listOf("values-v33", "values-night-v33")) {
            val launch = style(variant, "LaunchTheme")
            assertEquals("@style/SchulpilotSplashTheme", launch.getAttribute("parent"))
            assertEquals("icon_preferred", item(launch, "android:windowSplashScreenBehavior"))
        }
    }

    @Test fun systemSplashUsesSquareRgbaPng() {
        // PNG format only: export_brand's Python pixel tests verify mask safety.
        DataInputStream(res.resolve("drawable-nodpi/schulpilot_splash_logo.png")
            .inputStream().buffered()).use { input ->
            val signature = ByteArray(8)
            input.readFully(signature)
            assertArrayEquals(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 13, 10, 26, 10), signature)
            assertEquals("PNG must start with the 13-byte IHDR chunk", 13, input.readInt())
            val chunkType = ByteArray(4)
            input.readFully(chunkType)
            assertEquals("IHDR", String(chunkType, Charsets.US_ASCII))
            assertEquals("Splash width", 512, input.readInt())
            assertEquals("Splash height", 512, input.readInt())
            assertEquals("Eight-bit channels", 8, input.readUnsignedByte())
            assertEquals("RGBA color type", 6, input.readUnsignedByte())
        }
    }

    @Test fun launcherUsesTheExistingFlutterActivityAndNormalThemeHandoff() {
        val manifest = xml(res.parentFile.resolve("AndroidManifest.xml"))
        val activities = manifest.getElementsByTagName("activity")
        val main = (0 until activities.length).map { activities.item(it) as Element }
            .single { it.getAttributeNS(android, "name") == ".MainActivity" }
        assertEquals("@style/LaunchTheme", main.getAttributeNS(android, "theme"))
        assertEquals("singleTop", main.getAttributeNS(android, "launchMode"))
        val metadata = main.getElementsByTagName("meta-data")
        val normal = (0 until metadata.length).map { metadata.item(it) as Element }
            .single { it.getAttributeNS(android, "name") == "io.flutter.embedding.android.NormalTheme" }
        assertEquals("@style/NormalTheme", normal.getAttributeNS(android, "resource"))
    }
}
