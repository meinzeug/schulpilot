import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPath = System.getenv("SCHULPILOT_SIGNING_PROPERTIES")
val uploadProperties = Properties()
if (!signingPath.isNullOrBlank()) {
    val signingFile = file(signingPath)
    if (!signingFile.isFile) {
        throw GradleException("SCHULPILOT_SIGNING_PROPERTIES must name an existing external properties file")
    }
    signingFile.inputStream().use { uploadProperties.load(it) }
    if (listOf("storeFile", "storePassword", "keyAlias", "keyPassword").any {
            uploadProperties.getProperty(it).isNullOrBlank()
        } || !file(uploadProperties.getProperty("storeFile", "")).isFile) {
        throw GradleException("External upload signing requires an existing keystore and all four signing properties")
    }
}
val hasUploadKey = !signingPath.isNullOrBlank()
if (System.getenv("SCHULPILOT_STORE_BUILD") == "true" && !hasUploadKey) {
    throw GradleException("Store builds require an external SCHULPILOT_SIGNING_PROPERTIES file")
}

// Always guard Play release packaging, even when SCHULPILOT_STORE_BUILD was omitted.
// The direct development flavor may keep its existing debug-signed release workflow.
val verifyPlayUploadSigning by tasks.registering {
    doLast {
        if (!hasUploadKey) {
            throw GradleException("Play release builds require an external SCHULPILOT_SIGNING_PROPERTIES file; use playDebug for local development")
        }
    }
}
tasks.matching {
    it.name in setOf("prePlayReleaseBuild", "validateSigningPlayRelease", "packagePlayRelease", "packagePlayReleaseBundle", "signPlayReleaseBundle")
}.configureEach {
    dependsOn(verifyPlayUploadSigning)
}

android {
    namespace = "de.dorfspy.schulpilot"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.dorfspy.schulpilot"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("direct") {
            dimension = "distribution"
            if (!hasUploadKey) signingConfig = signingConfigs.getByName("debug")
        }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadProperties.getProperty("storeFile"))
                storePassword = uploadProperties.getProperty("storePassword")
                keyAlias = uploadProperties.getProperty("keyAlias")
                keyPassword = uploadProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    "playImplementation"("com.google.android.play:app-update:2.1.0")
}
