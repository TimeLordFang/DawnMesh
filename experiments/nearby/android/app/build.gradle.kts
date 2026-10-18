plugins { id("com.android.application") }
android {
    namespace = "dev.dawnmesh.nearbyprobe"
    compileSdk { version = release(37) { minorApiLevel = 2 } }
    defaultConfig {
        applicationId = "dev.dawnmesh.nearbyprobe"
        minSdk = 26
        targetSdk = 37
        versionCode = 2
        versionName = "0.1.1"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
dependencies {
    implementation("com.google.android.gms:play-services-nearby:19.5.1")
    testImplementation("junit:junit:4.13.2")
}
