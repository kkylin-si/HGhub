pluginManagement {
    repositories {
        // Actions 上 Maven Central 有时会把大包转到 GitHub Releases，那边容易 504。
        if (System.getenv("CI") == "true") {
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        if (System.getenv("CI") == "true") {
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://maven.aliyun.com/repository/google") }
        }
        google()
        mavenCentral()
    }
}

rootProject.name = "HGhub"
include(":app")
