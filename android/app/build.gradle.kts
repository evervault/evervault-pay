import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

val localProperties = Properties().apply {
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) {
        load(FileInputStream(localFile))
    }
}

val evervaultAppId: String = localProperties.getProperty("EVERVAULT_APP_ID") ?: ""
val evervaultMerchantId: String = localProperties.getProperty("EVERVAULT_MERCHANT_ID") ?: ""
val enableGooglePayAuthorization: Boolean =
    localProperties.getProperty("ENABLE_GOOGLE_PAY_AUTHORIZATION")?.toBooleanStrictOrNull() ?: false
val googlePayAuthorizationResult: String =
    localProperties.getProperty("GOOGLE_PAY_AUTHORIZATION_RESULT", "accept").lowercase()

require(googlePayAuthorizationResult in setOf("accept", "reject")) {
    "GOOGLE_PAY_AUTHORIZATION_RESULT must be 'accept' or 'reject'"
}

android {
    defaultConfig {
        buildConfigField("String", "EVERVAULT_APP_ID", "\"$evervaultAppId\"")
        buildConfigField("String", "EVERVAULT_MERCHANT_ID", "\"$evervaultMerchantId\"")
        buildConfigField("boolean", "ENABLE_GOOGLE_PAY_AUTHORIZATION", enableGooglePayAuthorization.toString())
        buildConfigField("String", "GOOGLE_PAY_AUTHORIZATION_RESULT", "\"$googlePayAuthorizationResult\"")
    }
}

android {
    namespace = "com.evervault.samplepayapp"
    compileSdk = 34
    // Keep in step with buildToolsVersions in flake.nix.
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "com.evervault.samplepayapp"
        minSdk = 24
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
        viewBinding = true
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    defaultConfig {
        // Temporary until upgrade to 34
        configurations.all {
            resolutionStrategy {
                force("androidx.emoji2:emoji2-views-helper:1.3.0")
                force("androidx.emoji2:emoji2:1.3.0")
                force("androidx.core:core-ktx:1.10.1")
            }
        }
    }
}

dependencies {
    implementation(project(":googlepay"))

    val lifecycleVersion = "2.6.1"

    implementation("com.google.pay.button:compose-pay-button:0.1.3")

    val composeBom = platform("androidx.compose:compose-bom:2023.03.00")
    implementation(composeBom)
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")

    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.activity:activity-compose:1.6.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:$lifecycleVersion")
    implementation("androidx.activity:activity-ktx:1.6.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.1")

    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4:1.6.0")

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.lifecycle.runtime.compose)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}