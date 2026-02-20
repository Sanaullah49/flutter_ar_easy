import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.example.flutter_ar_easy"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

configurations.configureEach {
    exclude(group = "com.android.support")
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {

    namespace = "com.example.flutter_ar_easy"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    buildFeatures {
        viewBinding = true
    }


    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    // Sceneform 1.17.1 is binary-compatible with ARCore 1.15.x APIs.
    implementation("com.google.ar:core:1.15.0")
    implementation("com.google.ar.sceneform:sceneform-base:1.17.1")
    implementation("com.google.ar.sceneform.ux:sceneform-ux:1.17.1")
    implementation("com.google.ar.sceneform:assets:1.17.1")
    implementation("androidx.lifecycle:lifecycle-common:2.10.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
