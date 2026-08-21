allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            if (android.namespace == null) {
                // Tự động gán namespace cho các thư viện cũ để vượt qua kiểm tra AGP mới
                android.namespace = when (project.name) {
                    "flutter_app_badger" -> "fr.g123k.flutterappbadge.flutterappbadger"
                    "speech_to_text" -> "com.csdcorp.speech_to_text"
                    else -> "com.generated." + project.name.replace("_", ".")
                }
            }
            // Đồng bộ compileSdkVersion với dự án chính
            android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
