#!/usr/bin/env python3
"""
Prépare le projet Android de l'application Yawi (Flutter).

Le dossier android/ est généré par la version de Flutter installée (`flutter create`),
ce qui garantit des fichiers Gradle compatibles avec cette version ; ce script y applique
ensuite la configuration Yawi. Il est idempotent : on peut le relancer sans risque.

  python3 tool/prepare_android.py            # génère (si besoin) puis configure
  python3 tool/prepare_android.py --no-create  # configure seulement

Ce qu'il applique :
  - identifiant gn.yawi.app, nom « Yawi », icônes, écran de lancement, sonnerie ;
  - SDK : compile/target 36 minimum (exigence Google Play depuis le 31/08/2026), min 24 ;
  - signature release via android/key.properties (sinon signature de debug, pour tester) ;
  - Firebase (notifications) si android/app/google-services.json est présent ;
  - permissions : Internet, localisation, notifications, vibration ; requêtes tel:/https:/wa.me.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
APP = ANDROID / "app"
APP_ID = "gn.yawi.app"
LABEL = "Yawi"
GOOGLE_SERVICES_VERSION = "4.4.2"


def log(msg):
    print(f"[yawi] {msg}")


def create():
    if (APP / "src" / "main" / "AndroidManifest.xml").exists():
        return
    log("Génération du projet Android avec flutter create…")
    # Sous Windows, « flutter » est un script flutter.bat : shutil.which le trouve via PATHEXT.
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("[yawi] Commande flutter introuvable. Ajoutez le dossier flutter\\bin au PATH, ou lancez :\n"
                 "  flutter create --platforms=android --org gn.yawi --project-name yawi --no-pub .\n"
                 "puis : python tool/prepare_android.py --no-create")
    subprocess.run(
        [flutter, "create", "--platforms=android", "--org", "gn.yawi", "--project-name", "yawi", "--no-pub", "."],
        cwd=ROOT, check=True, shell=sys.platform == "win32",
    )


def copy_resources():
    src = ROOT / "tool" / "android" / "res"
    dst = APP / "src" / "main" / "res"
    for f in src.rglob("*"):
        if f.is_file():
            target = dst / f.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, target)
    log("Ressources copiées (icônes, lancement, sonnerie).")


def sub_once(pattern, repl, text, what, flags=re.M):
    new, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n == 0:
        sys.exit(f"[yawi] Impossible de modifier : {what}. Vérifiez android/app/build.gradle.kts.")
    return new


def patch_gradle():
    kts = APP / "build.gradle.kts"
    if not kts.exists():
        sys.exit("[yawi] android/app/build.gradle.kts introuvable (Flutter récent requis : projets Gradle en Kotlin).")
    s = kts.read_text()

    s = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{APP_ID}"', s)
    s = re.sub(r'compileSdk\s*=\s*[^\n]+', 'compileSdk = maxOf(36, flutter.compileSdkVersion)', s, count=1)
    s = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = maxOf(24, flutter.minSdkVersion)', s, count=1)
    s = re.sub(r'targetSdk\s*=\s*[^\n]+', 'targetSdk = maxOf(36, flutter.targetSdkVersion)', s, count=1)

    # Lint « vital » des builds release : il plante sur certains JDK de CI (bug interne de lint, sans lien avec le code).
    if "checkReleaseBuilds" not in s:
        s = sub_once(r'(\nandroid \{\n)', r'\1    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n', s, "bloc android { }")

    # Désucrage Java 8+ (exigé par flutter_local_notifications)
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = sub_once(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', s, "compileOptions")
    if "desugar_jdk_libs" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'

    # Signature : key.properties (keystore de publication) ; à défaut, debug
    if "yawiKeystore" not in s:
        # Les imports vont en tête ; la lecture de key.properties après le bloc plugins {}
        # (Gradle n'accepte rien d'autre avant plugins {}).
        s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s
        s = sub_once(
            r'(plugins\s*\{[^}]*\}\n)',
            '\\1\n'
            'val yawiKeystore = Properties().apply {\n'
            '    val f = rootProject.file("key.properties")\n'
            '    if (f.exists()) load(FileInputStream(f))\n'
            '}\n',
            s, "plugins",
        )
        s = sub_once(
            r'(\n\s*buildTypes\s*\{)',
            '\n    signingConfigs {\n'
            '        create("release") {\n'
            '            if (yawiKeystore.isNotEmpty()) {\n'
            '                storeFile = file(yawiKeystore.getProperty("storeFile"))\n'
            '                storePassword = yawiKeystore.getProperty("storePassword")\n'
            '                keyAlias = yawiKeystore.getProperty("keyAlias")\n'
            '                keyPassword = yawiKeystore.getProperty("keyPassword")\n'
            '            }\n'
            '        }\n'
            '    }\n\\1',
            s, "buildTypes",
        )
        s = re.sub(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (yawiKeystore.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            s, count=1,
        )

    # Firebase Cloud Messaging
    has_firebase = (APP / "google-services.json").exists()
    if has_firebase and "com.google.gms.google-services" not in s:
        s = sub_once(r'(\n(\s*)id\("com\.android\.application"\)[^\n]*)', r'\1\n\2id("com.google.gms.google-services")', s, "plugins (com.android.application)")
    elif not has_firebase:
        # Sans google-services.json, le plugin ferait échouer le build : on le retire (relancer après ajout du fichier).
        s = re.sub(r'\n\s*id\("com\.google\.gms\.google-services"\)(?! version)[^\n]*', "", s)
    kts.write_text(s)

    settings = ANDROID / "settings.gradle.kts"
    if has_firebase and settings.exists():
        t = settings.read_text()
        if "com.google.gms.google-services" not in t:
            t = sub_once(
                r'(id\("dev\.flutter\.flutter-plugin-loader"\)[^\n]*\n)',
                f'\\1    id("com.google.gms.google-services") version "{GOOGLE_SERVICES_VERSION}" apply false\n',
                t, "settings.gradle.kts",
            )
            settings.write_text(t)
    log("Gradle configuré" + (" avec Firebase." if has_firebase else " (sans Firebase : notifications push désactivées)."))


PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
    "android.permission.WAKE_LOCK",
    "android.permission.CAMERA",  # scan des cartes de transport (navettes)
]

QUERIES = """    <queries>
        <intent><action android:name="android.intent.action.DIAL" /><data android:scheme="tel" /></intent>
        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>
        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="geo" /></intent>
        <intent><action android:name="android.intent.action.SENDTO" /><data android:scheme="mailto" /></intent>
        <intent><action android:name="android.intent.action.PROCESS_TEXT" /><data android:mimeType="text/plain" /></intent>
    </queries>
"""


def patch_manifest():
    m = APP / "src" / "main" / "AndroidManifest.xml"
    s = m.read_text()
    for p in PERMISSIONS:
        if p not in s:
            s = s.replace("<application", f'<uses-permission android:name="{p}" />\n    <application', 1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{LABEL}"', s, count=1)
    if "networkSecurityConfig" not in s:
        s = s.replace("<application", '<application\n        android:networkSecurityConfig="@xml/network_security_config"', 1)
    if "default_notification_channel_id" not in s:
        meta = (
            '        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="alertes" />\n'
            '        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat_yawi" />\n'
            '        <meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@color/yawi_braise" />\n'
        )
        s = s.replace("</application>", meta + "    </application>", 1)
    # Les requêtes d'intents remplacent celles du modèle (PROCESS_TEXT y compris)
    s = re.sub(r"\s*<queries>.*?</queries>\n?", "\n", s, flags=re.S)
    s = s.replace("</manifest>", QUERIES + "</manifest>", 1)
    m.write_text(s)
    log("Manifeste configuré (permissions, nom, canal de notification).")


def main():
    if "--no-create" not in sys.argv:
        create()
    copy_resources()
    patch_gradle()
    patch_manifest()
    log(f"Projet Android prêt : {APP_ID}")


if __name__ == "__main__":
    main()
