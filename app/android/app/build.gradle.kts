import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // 2026-09-08: google-services.json을 읽어서 Firebase.initializeApp()이
    // 네이티브 설정을 자동으로 찾게 해줌(FCM 다이제스트 알림용).
    id("com.google.gms.google-services")
}

// 2026-09-26: Play 스토어는 release 빌드에 디버그 키 서명을 안 받아줘서
// 정식 업로드 키(upload-keystore.jks)를 만들고, 그 경로/비밀번호를
// key.properties(git 추적 안 함, .gitignore 참고)에서 읽어옴 — 키
// 자체나 비밀번호를 코드에 직접 적지 않기 위함.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.issuepop.issue_pop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.issuepop.issue_pop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 2026-10-26(출시 전 점검 IP-12): 예전(2026-09-26)엔 key.properties가 없으면 디버그 키로 조용히 서명해서 빌드가 "성공"했는데,
            // 그렇게 만든 앱은 Play가 업로드를 거부하고 원인을 알기 어려웠음. 이제 릴리스 서명은 항상 release 키를 쓰고,
            // key.properties가 없으면 아래에서 빌드를 실패시킴(디버그 빌드·flutter run에는 영향 없음).
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// 릴리스 빌드(assembleRelease/bundleRelease 등)를 요청했는데 key.properties가 없으면 바로 실패시킴.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { task ->
        task.project == project && task.name.contains("Release", ignoreCase = true) &&
            (task.name.startsWith("assemble") || task.name.startsWith("bundle") || task.name.startsWith("package"))
    }
    if (releaseRequested && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "릴리스 빌드에는 ${keystorePropertiesFile.path} (업로드 키 정보)가 필요합니다. " +
                "이 파일 없이 만든 앱은 디버그 키로 서명돼 Play 업로드가 거부됩니다. 업로드 키가 있는 PC에서 빌드하세요."
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
