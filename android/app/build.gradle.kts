import com.android.build.OutputFile
import com.android.build.gradle.internal.api.BaseVariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.maleolabs.kecilin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.maleolabs.kecilin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Fail hard instead of silently signing with the debug key: a
            // debug-signed "release" can never update an installed build, and
            // it is easy to hand out without noticing.
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "android/key.properties is missing. Release builds must use " +
                        "the release keystore (see docs/releasing.md)."
                )
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                // Post-quantum crypto tables shipped with BouncyCastle: ~8 MB of
                // data that no PDF code path in this app can reach.
                "org/bouncycastle/pqc/**",
            )
        }
    }

    // Release APK assets are identified at a glance by app + version, so the
    // split APKs are named kecilin-<version>-<abi>.apk (for example
    // kecilin-1.0.0-arm64-v8a.apk). Outputs land in
    // build/app/outputs/apk/release/. The Flutter Gradle plugin still copies
    // default-named APKs into build/app/outputs/flutter-apk/; those copies are
    // NOT consumed by release.yml and exist only for `flutter`-tool convenience.
    // A universal APK (no ABI filter, only built by `flutter build apk` without
    // --split-per-abi) has no filter and keeps its default name.
    // applicationVariants is deprecated in AGP 9; this project pins AGP 8.11.1.
    applicationVariants.all {
        val variantVersionName = versionName
        outputs.all {
            val output = this as BaseVariantOutputImpl
            val abi = output.getFilter(OutputFile.ABI) ?: return@all
            output.outputFileName = "kecilin-$variantVersionName-$abi.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pure-Java PDF object model used by the "Ringan" (text preserving) mode.
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")

    // JVM-only tests for the pure-Java pieces (the PDF writer).
    testImplementation("junit:junit:4.13.2")
}
