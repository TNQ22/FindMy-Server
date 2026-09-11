import os
import shutil
import subprocess
import tempfile
import re

def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    android_dir = os.path.join(base_dir, 'android')
    
    # 1. Back up vital assets before recreating scaffold
    temp_dir = tempfile.mkdtemp(prefix='findmy_android_backup_')
    backup_res = os.path.join(temp_dir, 'res')
    backup_manifest = os.path.join(temp_dir, 'AndroidManifest.xml')
    backup_keystore = os.path.join(temp_dir, 'debug.store')
    backup_main_activity = os.path.join(temp_dir, 'MainActivity.kt')
    
    res_src = os.path.join(android_dir, 'app', 'src', 'main', 'res')
    if os.path.exists(res_src):
        shutil.copytree(res_src, backup_res)
        print(f"Backed up custom icons and res from {res_src}")
        
    manifest_src = os.path.join(android_dir, 'app', 'src', 'main', 'AndroidManifest.xml')
    if os.path.exists(manifest_src):
        shutil.copy(manifest_src, backup_manifest)
        print(f"Backed up AndroidManifest.xml")
        
    keystore_src = os.path.join(android_dir, 'app', 'debug.store')
    if os.path.exists(keystore_src):
        shutil.copy(keystore_src, backup_keystore)
        print(f"Backed up debug.store")
        
    activity_src = os.path.join(android_dir, 'app', 'src', 'main', 'kotlin', 'de', 'dchristl', 'headlesshaystack', 'MainActivity.kt')
    if os.path.exists(activity_src):
        shutil.copy(activity_src, backup_main_activity)
        print(f"Backed up MainActivity.kt")

    # 2. Clean and recreate clean scaffold
    if os.path.exists(android_dir):
        shutil.rmtree(android_dir, ignore_errors=True)
        print("Cleaned old android scaffold.")

    print("Running flutter create --no-pub --platforms=android --org de.dchristl .")
    subprocess.run(['flutter', 'create', '--no-pub', '--platforms=android', '--org', 'de.dchristl', '.'], cwd=base_dir, check=True)

    # 3. Restore vital assets
    app_dir = os.path.join(android_dir, 'app')
    main_dir = os.path.join(app_dir, 'src', 'main')

    # Restore res (custom app icons)
    if os.path.exists(backup_res):
        target_res = os.path.join(main_dir, 'res')
        shutil.copytree(backup_res, target_res, dirs_exist_ok=True)
        print("Restored original app icons (OpenHaystack / FindMy) into res/")

    # Restore AndroidManifest.xml
    if os.path.exists(backup_manifest):
        shutil.copy(backup_manifest, os.path.join(main_dir, 'AndroidManifest.xml'))
        print("Restored AndroidManifest.xml")

    # Restore debug.store
    if os.path.exists(backup_keystore):
        shutil.copy(backup_keystore, os.path.join(app_dir, 'debug.store'))
        print("Restored debug.store signing key")

    # Restore MainActivity.kt under package de.dchristl.headlesshaystack
    if os.path.exists(backup_main_activity):
        target_kotlin_pkg = os.path.join(main_dir, 'kotlin', 'de', 'dchristl', 'headlesshaystack')
        os.makedirs(target_kotlin_pkg, exist_ok=True)
        shutil.copy(backup_main_activity, os.path.join(target_kotlin_pkg, 'MainActivity.kt'))
        
        # Remove scaffold-generated macless_haystack activity dir if present
        scaffold_pkg = os.path.join(main_dir, 'kotlin', 'de', 'dchristl', 'macless_haystack')
        if os.path.exists(scaffold_pkg):
            shutil.rmtree(scaffold_pkg, ignore_errors=True)
        print("Restored MainActivity.kt in package de.dchristl.headlesshaystack")

    # 4. Write clean android/app/build.gradle.kts
    build_gradle_kts = os.path.join(app_dir, 'build.gradle.kts')
    gradle_content = '''plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.dchristl.headlesshaystack"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "de.dchristl.headlesshaystack"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = "androiddebugkey"
            keyPassword = "android"
            storeFile = file("debug.store")
            storePassword = "android"
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
'''
    with open(build_gradle_kts, 'w', encoding='utf-8') as f:
        f.write(gradle_content)
    print("Wrote clean app/build.gradle.kts with signing config (V1+V2), applicationId, compileSdk 36, and minSdk 24.")

    # 5. Write android/gradle.properties
    gradle_props = os.path.join(android_dir, 'gradle.properties')
    props_content = '''org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
org.gradle.parallel=false
android.useAndroidX=true
android.enableJetifier=true
'''
    with open(gradle_props, 'w', encoding='utf-8') as f:
        f.write(props_content)
    print("Wrote android/gradle.properties")

    # Cleanup temp
    shutil.rmtree(temp_dir, ignore_errors=True)
    print("Android scaffold preparation completed successfully!")

if __name__ == '__main__':
    main()
