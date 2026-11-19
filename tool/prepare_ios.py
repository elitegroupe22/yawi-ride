#!/usr/bin/env python3
"""
Prépare le projet iOS de l'application Yawi (Flutter).

Comme pour Android, le dossier ios/ est généré par la version de Flutter installée
(`flutter create`), puis ce script y applique la configuration Yawi. Il est idempotent.
Il fonctionne sur n'importe quel système (la compilation, elle, exige un Mac avec Xcode 26+).

  python3 tool/prepare_ios.py              # génère (si besoin) puis configure
  python3 tool/prepare_ios.py --no-create  # configure seulement

Ce qu'il applique :
  - identifiant gn.yawi.app, nom « Yawi », iPhone uniquement, portrait, iOS 15 minimum ;
  - icône (1024 px sans transparence), écran de lancement bleu nuit avec le symbole Yawi ;
  - textes des autorisations (localisation, appareil photo, photos), notifications en arrière-plan,
    déclaration de chiffrement (aucun chiffrement propriétaire), schémas tel:/https:/whatsapp: ;
  - sonneries Yawi (sonnerie.wav, bip.wav) dans le bundle, utilisées par les notifications push ;
  - capacité « Push Notifications » (Runner.entitlements) ;
  - Firebase si ios/Runner/GoogleService-Info.plist est présent (ajouté au projet Xcode).

Aucune dépendance : Python 3 suffit.
"""
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
RUNNER = IOS / "Runner"
PBX = IOS / "Runner.xcodeproj" / "project.pbxproj"
TOOL = ROOT / "tool" / "ios"
BUNDLE_ID = "gn.yawi.app"
LABEL = "Yawi"
MIN_IOS = "15.0"
NUIT = (0x1B, 0x27, 0x35)  # couleur de fond de l'écran de lancement


def log(msg):
    print(f"[yawi] {msg}")


def create():
    if (RUNNER / "Info.plist").exists():
        return
    log("Génération du projet iOS avec flutter create…")
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("[yawi] Commande flutter introuvable. Lancez :\n"
                 "  flutter create --platforms=ios --org gn.yawi --project-name yawi --no-pub .\n"
                 "puis : python3 tool/prepare_ios.py --no-create")
    subprocess.run([flutter, "create", "--platforms=ios", "--org", "gn.yawi", "--project-name", "yawi", "--no-pub", "."],
                   cwd=ROOT, check=True, shell=sys.platform == "win32")


def info_plist():
    path = RUNNER / "Info.plist"
    with path.open("rb") as f:
        p = plistlib.load(f)
    p["CFBundleDisplayName"] = LABEL
    p["CFBundleName"] = LABEL
    p["NSLocationWhenInUseUsageDescription"] = (
        "Yawi utilise votre position pour vous trouver un chauffeur à proximité, vous guider et partager le trajet en cours.")
    p["NSCameraUsageDescription"] = (
        "Yawi utilise l'appareil photo pour scanner les cartes de transport des passagers, photographier les pièces du dossier chauffeur et votre photo de profil.")
    p["NSPhotoLibraryUsageDescription"] = (
        "Yawi accède à vos photos pour joindre les pièces du dossier chauffeur et votre photo de profil.")
    p["UIBackgroundModes"] = ["remote-notification", "voip", "audio"]
    p["NSMicrophoneUsageDescription"] = (
        "Yawi utilise le micro pour les appels par internet avec votre chauffeur, votre client ou le service client.")
    p["ITSAppUsesNonExemptEncryption"] = False  # HTTPS uniquement : pas de déclaration d'exportation
    p["LSApplicationQueriesSchemes"] = ["tel", "https", "whatsapp", "sms"]
    p["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
    p.pop("UISupportedInterfaceOrientations~ipad", None)
    p["UIRequiresFullScreen"] = True
    p["FirebaseAppDelegateProxyEnabled"] = True
    with path.open("wb") as f:
        plistlib.dump(p, f)
    log("Info.plist configuré (nom, autorisations, notifications, schémas).")


def app_delegate():
    """AppDelegate Yawi : délégué des notifications et appels VoIP (PushKit → CallKit)."""
    path = RUNNER / "AppDelegate.swift"
    current = path.read_text() if path.exists() else ""
    if "FlutterImplicitEngineDelegate" not in current and "GeneratedPluginRegistrant.register(with: self)" in current:
        # Ancien modèle Flutter (sans scènes) : on garde son enregistrement des plugins.
        tpl = (TOOL / "AppDelegate.swift").read_text()
        tpl = tpl.replace(", FlutterImplicitEngineDelegate", "")
        tpl = re.sub(r"\n  func didInitializeImplicitFlutterEngine.*?\n  }\n", "\n", tpl, flags=re.S)
        tpl = tpl.replace("    voipRegistry = registry\n", "    voipRegistry = registry\n    GeneratedPluginRegistrant.register(with: self)\n")
    else:
        tpl = (TOOL / "AppDelegate.swift").read_text()
    path.write_text(tpl)
    log("AppDelegate : notifications et appels VoIP configurés.")


def assets():
    icons = RUNNER / "Assets.xcassets" / "AppIcon.appiconset"
    shutil.rmtree(icons, ignore_errors=True)
    icons.mkdir(parents=True)
    shutil.copyfile(TOOL / "AppIcon" / "icon-1024.png", icons / "icon-1024.png")
    (icons / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    launch = RUNNER / "Assets.xcassets" / "LaunchImage.imageset"
    launch.mkdir(parents=True, exist_ok=True)
    for f in (TOOL / "LaunchImage").glob("*.png"):
        shutil.copyfile(f, launch / f.name)
    story = RUNNER / "Base.lproj" / "LaunchScreen.storyboard"
    s = story.read_text()
    r, g, b = (c / 255 for c in NUIT)
    color = f'<color key="backgroundColor" red="{r:.4f}" green="{g:.4f}" blue="{b:.4f}" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>'
    s = re.sub(r'<color key="backgroundColor"[^>]*/>', color, s)
    from struct import unpack
    with open(TOOL / "LaunchImage" / "LaunchImage.png", "rb") as png:
        w, h = unpack(">II", png.read(24)[16:24])
    s = re.sub(r'<image name="LaunchImage" width="[0-9.]+" height="[0-9.]+"/>', f'<image name="LaunchImage" width="{w}" height="{h}"/>', s)
    story.write_text(s)
    log("Icône et écran de lancement appliqués.")


def copy_runner_files():
    for f in (TOOL / "Runner").iterdir():
        shutil.copyfile(f, RUNNER / f.name)


def _uid(seed):
    """Identifiant Xcode stable (24 caractères hexadécimaux) : relancer le script ne crée pas de doublon."""
    import hashlib
    return hashlib.md5(f"yawi:{seed}".encode()).hexdigest()[:24].upper()


FILE_TYPES = {".wav": "audio.wav", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements"}


def pbxproj():
    s = PBX.read_text()
    # Identifiant, cible minimale, iPhone uniquement (évite les captures iPad obligatoires).
    s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]*\.RunnerTests;", f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.RunnerTests;", s)
    s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = (?![^;]*RunnerTests)[^;]+;", f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};", s)
    s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS};", s)
    s = re.sub(r'TARGETED_DEVICE_FAMILY = "?[0-9,]+"?;', "TARGETED_DEVICE_FAMILY = 1;", s)

    files = ["sonnerie.wav", "bip.wav", "Runner.entitlements"]
    if (RUNNER / "GoogleService-Info.plist").exists():
        files.append("GoogleService-Info.plist")
    else:
        log("GoogleService-Info.plist absent : l'application iOS sera construite sans notifications push.")

    group = re.search(r"\w{24} /\* Runner \*/ = \{\s*isa = PBXGroup;\s*children = \(\n", s)
    phases = [m for m in re.finditer(r"\w{24} /\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);", s, re.S)
              if "Assets.xcassets" in m.group(1)]
    if not group or not phases:
        sys.exit("[yawi] project.pbxproj : groupe Runner ou phase Resources introuvable (modèle Flutter inattendu).")
    phase_files_at = s.index("files = (\n", phases[0].start()) + len("files = (\n")

    refs, builds, children, resources = [], [], [], []
    for name in files:
        if f"/* {name} */ = {{isa = PBXFileReference" in s:
            continue
        ref, build = _uid(f"ref:{name}"), _uid(f"build:{name}")
        ftype = FILE_TYPES[Path(name).suffix]
        refs.append(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = "{name}"; sourceTree = "<group>"; }};\n')
        children.append(f"\t\t\t\t{ref} /* {name} */,\n")
        if name != "Runner.entitlements":  # un fichier de droits n'est pas une ressource du bundle
            builds.append(f"\t\t{build} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n")
            resources.append(f"\t\t\t\t{build} /* {name} in Resources */,\n")

    # Insertions de la fin vers le début pour garder les positions valides.
    edits = [(phase_files_at, "".join(resources)), (group.end(), "".join(children)),
             (s.index("/* End PBXFileReference section */"), "".join(refs)),
             (s.index("/* End PBXBuildFile section */"), "".join(builds))]
    for pos, text in sorted(edits, key=lambda e: e[0], reverse=True):
        s = s[:pos] + text + s[pos:]

    # Capacité Push Notifications sur les configurations de la cible Runner.
    s = re.sub(r"(\n(\t+)PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(BUNDLE_ID) + r";)",
               lambda m: f"\n{m.group(2)}CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;{m.group(1)}", s)
    s = re.sub(r"(\t+CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;\n)+", lambda m: m.group(0).split("\n")[0] + "\n", s)
    PBX.write_text(s)
    log(f"Projet Xcode : {BUNDLE_ID}, iOS {MIN_IOS}+, iPhone, sonneries, push" +
        (", Firebase." if "GoogleService-Info.plist" in files else "."))


def podfile():
    """Si CocoaPods est utilisé, impose la même version minimale d'iOS aux dépendances."""
    pod = IOS / "Podfile"
    if not pod.exists():
        return
    s = pod.read_text()
    s = re.sub(r"^#?\s*platform :ios,.*$", f"platform :ios, '{MIN_IOS}'", s, count=1, flags=re.M)
    pod.write_text(s)


def main():
    if "--no-create" not in sys.argv:
        create()
    if not (RUNNER / "Info.plist").exists():
        sys.exit("[yawi] Dossier ios/ introuvable : lancez d'abord flutter create --platforms=ios .")
    copy_runner_files()
    info_plist()
    app_delegate()
    assets()
    pbxproj()
    podfile()
    log(f"Projet iOS prêt : {BUNDLE_ID}")


if __name__ == "__main__":
    main()
