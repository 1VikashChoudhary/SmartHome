import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.smarthome.smarthome_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.smarthome.smarthome_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProperties.getProperty("storeFile")
            if (!storePath.isNullOrBlank()) {
                storeFile = rootProject.file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            val hasReleaseKeystore = !keystoreProperties.getProperty("storeFile").isNullOrBlank()
            val allowDebugFallback =
                project.findProperty("allowDebugReleaseSigning")?.toString()?.toBoolean() == true
            signingConfig = when {
                hasReleaseKeystore -> signingConfigs.getByName("release")
                allowDebugFallback -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val runningReleaseTask = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    val hasReleaseKeystore = !keystoreProperties.getProperty("storeFile").isNullOrBlank()
    val allowDebugFallback =
        project.findProperty("allowDebugReleaseSigning")?.toString()?.toBoolean() == true
    if (runningReleaseTask && !hasReleaseKeystore && !allowDebugFallback) {
        throw GradleException(
            "Release builds require app/android/key.properties with a valid release keystore " +
            "(or pass -PallowDebugReleaseSigning=true explicitly for local testing)."
        )
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
