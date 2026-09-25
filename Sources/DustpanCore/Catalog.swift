import Foundation

/// Everything Dustpan knows how to find. Add a rule here to teach it something new.
public enum Catalog {
    public static let rules: [Rule] =
        caches + xcode + packages + projects + toolchains + virtualization + aiModels + applications + files

    public static func rule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    // MARK: - App caches

    static let caches: [Rule] = [
        Rule(
            "app-update-leftovers", "App update leftovers", .caches, .safe,
            summary: "Installers that apps' built-in updaters downloaded and never cleaned up.",
            aftermath: "Nothing changes. Apps download the next update when there is one.",
            locations: [.children("~/Library/Caches", matching: ["*.ShipIt"])]
        ),
        Rule(
            "browser-caches", "Browser & Electron caches", .caches, .safe,
            summary: "Web caches kept by Chromium browsers and Electron apps such as Slack, Discord, VS Code and Claude.",
            aftermath: "Apps rebuild them as you use them. Quit the apps first.",
            locations: [
                .item("~/Library/Application Support/*/Cache", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/Code Cache", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/GPUCache", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/DawnGraphiteCache", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/DawnWebGPUCache", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/Service Worker/CacheStorage", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/Google/Chrome/*/Service Worker/CacheStorage"),
                .item("~/Library/Application Support/Google/Chrome/*/Code Cache"),
                .item("~/Library/Application Support/Google/Chrome/*/GPUCache"),
                .item("~/Library/Application Support/BraveSoftware/Brave-Browser/*/Service Worker/CacheStorage"),
                .item("~/Library/Application Support/Microsoft Edge/*/Service Worker/CacheStorage"),
                .item("~/Library/Application Support/Arc/User Data/*/Service Worker/CacheStorage"),
            ],
            note: "Quit the browsers and apps whose caches you clear."
        ),
        Rule(
            "editor-caches", "Code editor caches", .caches, .safe,
            summary: "Compiled code and downloaded extension packages cached by VS Code and its forks (Cursor, Windsurf…).",
            aftermath: "The editor rebuilds them on its next launch.",
            locations: [
                .item("~/Library/Application Support/*/CachedData", excluding: ["com.apple.*"]),
                .item("~/Library/Application Support/*/CachedExtensionVSIXs", excluding: ["com.apple.*"]),
            ],
            quitFirst: ["VS Code"]
        ),
        Rule(
            "sandboxed-app-caches", "App Store app caches", .caches, .safe,
            summary: "Caches of sandboxed apps (most App Store apps) inside ~/Library/Containers.",
            aftermath: "Apps rebuild them as needed. Quit the apps first.",
            locations: [.item("~/Library/Containers/*/Data/Library/Caches", excluding: ["com.apple.*"])],
            note: "Only visible with Full Disk Access."
        ),
        Rule(
            "logs", "Logs & crash reports", .caches, .safe,
            summary: "Log files and crash reports apps have written.",
            aftermath: "Nothing, unless you're in the middle of debugging something.",
            locations: [.children("~/Library/Logs")]
        ),
        Rule(
            "app-caches", "Other app caches", .caches, .safe,
            summary: "Everything else apps keep in ~/Library/Caches: thumbnails, downloads, compiled code.",
            aftermath: "Apps rebuild what they need; the first launch afterwards can be a little slower. Quit apps first.",
            locations: [
                .children("~/Library/Caches", excluding: [
                    // macOS's own caches: tiny, and system services expect them.
                    "com.apple.*", "CloudKit", "FamilyCircle", "GameKit", "PassKit", "GeoServices",
                    "SiriEntityCache", "Animoji", "AMSDataMigratorTool", "askpermissiond", "TrickPlay",
                    "LSMImageCache", "SharedImageCache", "AAProfilePicture_*",
                ]),
            ],
            isCatchAll: true
        ),
    ]

    // MARK: - Xcode & Simulators

    static let xcode: [Rule] = [
        Rule(
            "xcode-derived-data", "Xcode DerivedData", .xcode, .safe,
            summary: "Build products and indexes for every project you've opened in Xcode.",
            aftermath: "Xcode rebuilds what it needs; each project's next build takes longer.",
            locations: [.item("~/Library/Developer/Xcode/DerivedData")],
            quitFirst: ["Xcode"]
        ),
        Rule(
            "xcode-device-support", "Device support files", .xcode, .safe,
            summary: "Debug symbols Xcode copied from every device and OS version you've connected.",
            aftermath: "Xcode copies them again the next time you connect that device.",
            locations: [
                .children("~/Library/Developer/Xcode/iOS DeviceSupport"),
                .children("~/Library/Developer/Xcode/watchOS DeviceSupport"),
                .children("~/Library/Developer/Xcode/tvOS DeviceSupport"),
                .children("~/Library/Developer/Xcode/visionOS DeviceSupport"),
                .children("~/Library/Developer/Xcode/macOS DeviceSupport"),
            ]
        ),
        Rule(
            "xcode-previews", "SwiftUI preview simulators", .xcode, .safe,
            summary: "Simulator devices Xcode creates to render SwiftUI previews.",
            aftermath: "Xcode recreates them the next time you open a preview.",
            locations: [.item("~/Library/Developer/Xcode/UserData/Previews")],
            quitFirst: ["Xcode"]
        ),
        Rule(
            "xcode-caches", "Xcode caches", .xcode, .safe,
            summary: "Xcode's own caches, playground devices and test devices.",
            aftermath: "Xcode rebuilds them as needed.",
            locations: [
                .item("~/Library/Caches/com.apple.dt.Xcode"),
                .item("~/Library/Developer/Xcode/UserData/IB Support"),
                .item("~/Library/Developer/XCPGDevices"),
                .item("~/Library/Developer/XCTestDevices"),
            ],
            quitFirst: ["Xcode"]
        ),
        Rule(
            "simulator-caches", "Simulator caches", .xcode, .safe,
            summary: "Shared caches the Simulator builds for each runtime.",
            aftermath: "Rebuilt the next time a simulator boots, so that first boot is slower.",
            locations: [.item("~/Library/Developer/CoreSimulator/Caches")],
            quitFirst: ["Simulator"]
        ),
        Rule(
            "simulator-unavailable", "Orphaned simulators", .xcode, .safe,
            summary: "Simulators whose OS version is no longer installed. They can't boot anymore.",
            aftermath: "Nothing. They were already unusable.",
            discovery: .unavailableSimulators,
            cleanup: .command("xcrun simctl delete unavailable")
        ),
        Rule(
            "simulator-data", "Simulator contents", .xcode, .caution,
            summary: "Apps and data installed inside your simulators.",
            aftermath: "Every simulator goes back to a fresh state; you reinstall your apps on them.",
            locations: [.item("~/Library/Developer/CoreSimulator/Devices")],
            cleanup: .command("xcrun simctl shutdown all && xcrun simctl erase all")
        ),
        Rule(
            "simulator-runtimes", "Simulator runtimes", .xcode, .review,
            summary: "Whole simulator OS versions (iOS, watchOS, visionOS…) installed through Xcode.",
            aftermath: "Reinstall one from Xcode → Settings → Components when you need it.",
            discovery: .simulatorRuntimes,
            cleanup: .command("xcrun simctl runtime delete <identifier>")
        ),
        Rule(
            "xcode-archives", "Xcode archives", .xcode, .review,
            summary: "Archived builds of your apps, listed in Xcode's Organizer.",
            aftermath: "Gone for good once you empty the Trash. Keep the archives of releases you still support: their dSYMs symbolicate crash reports.",
            locations: [.children("~/Library/Developer/Xcode/Archives")]
        ),
    ]

    // MARK: - Package managers

    static let packages: [Rule] = [
        Rule(
            "homebrew-cache", "Homebrew downloads", .packages, .safe,
            summary: "Bottles and source archives Homebrew downloaded while installing.",
            aftermath: "Homebrew downloads them again only if you reinstall something.",
            locations: [.item("~/Library/Caches/Homebrew")],
            note: "brew cleanup --prune=all also removes old versions of installed formulae."
        ),
        Rule(
            "npm-cache", "npm cache", .packages, .safe,
            summary: "Every package npm has downloaded.",
            aftermath: "npm downloads packages again when a project needs them.",
            locations: [.item("~/.npm/_cacache")]
        ),
        Rule(
            "yarn-cache", "Yarn cache", .packages, .safe,
            summary: "Packages downloaded by Yarn.",
            aftermath: "Yarn downloads them again when a project needs them.",
            locations: [.item("~/Library/Caches/Yarn"), .item("~/.yarn/berry/cache")]
        ),
        Rule(
            "pnpm-store", "pnpm store", .packages, .caution,
            summary: "pnpm's global package store and metadata cache.",
            aftermath: "pnpm downloads packages again on the next install.",
            locations: [
                .item("~/Library/pnpm/store"), .item("~/.local/share/pnpm/store"),
                .item("~/.pnpm-store"), .item("~/Library/Caches/pnpm"),
            ],
            note: "Projects hard-link files from the store, so the space frees up only once their node_modules are gone too. pnpm store prune is the gentler option."
        ),
        Rule(
            "bun-cache", "Bun cache", .packages, .safe,
            summary: "Packages downloaded by Bun.",
            aftermath: "Bun downloads them again when a project needs them.",
            locations: [.item("~/.bun/install/cache"), .item("~/Library/Caches/bun")]
        ),
        Rule(
            "pip-cache", "pip cache", .packages, .safe,
            summary: "Wheels and downloads cached by pip.",
            aftermath: "pip downloads them again when needed.",
            locations: [.item("~/Library/Caches/pip")]
        ),
        Rule(
            "uv-cache", "uv cache", .packages, .safe,
            summary: "Python packages downloaded and built by uv.",
            aftermath: "uv downloads them again the next time a project needs them.",
            locations: [.item("~/.cache/uv"), .item("~/Library/Caches/uv")],
            note: "uv clones files into your virtual environments, so the space actually freed can be lower than shown."
        ),
        Rule(
            "poetry-cache", "Poetry cache", .packages, .safe,
            summary: "Packages and metadata cached by Poetry.",
            aftermath: "Poetry downloads them again when needed.",
            locations: [.item("~/Library/Caches/pypoetry")]
        ),
        Rule(
            "conda-packages", "Conda package cache", .packages, .safe,
            summary: "Package archives and extracted packages kept by Conda.",
            aftermath: "Conda downloads them again when an environment needs them.",
            locations: [
                .item("~/miniconda3/pkgs"), .item("~/anaconda3/pkgs"), .item("~/miniforge3/pkgs"),
                .item("~/mambaforge/pkgs"), .item("~/opt/anaconda3/pkgs"), .item("~/opt/miniconda3/pkgs"),
            ],
            cleanup: .command("conda clean --all"),
            note: "Environments hard-link these files, so let Conda decide what's unused."
        ),
        Rule(
            "pyinstaller-cache", "PyInstaller cache", .packages, .safe,
            summary: "Binaries PyInstaller already processed for earlier builds.",
            aftermath: "Rebuilt on your next PyInstaller build, which runs a bit slower.",
            locations: [.item("~/Library/Application Support/pyinstaller")]
        ),
        Rule(
            "gradle-cache", "Gradle caches", .packages, .safe,
            summary: "Dependencies and build caches downloaded by Gradle (Android, Kotlin, Java).",
            aftermath: "Gradle downloads dependencies again on the next build.",
            locations: [.item("~/.gradle/caches")],
            quitFirst: ["Android Studio"]
        ),
        Rule(
            "gradle-wrappers", "Gradle distributions", .packages, .caution,
            summary: "Gradle versions downloaded by your projects' Gradle wrappers.",
            aftermath: "Each project downloads its Gradle version again on its next build.",
            locations: [.children("~/.gradle/wrapper/dists")]
        ),
        Rule(
            "maven-repository", "Maven repository", .packages, .caution,
            summary: "Every Java dependency Maven has downloaded.",
            aftermath: "Maven downloads dependencies again on the next build.",
            locations: [.item("~/.m2/repository")]
        ),
        Rule(
            "cocoapods-cache", "CocoaPods cache", .packages, .safe,
            summary: "Pods CocoaPods downloaded for your projects.",
            aftermath: "CocoaPods downloads them again on the next pod install.",
            locations: [.item("~/Library/Caches/CocoaPods")]
        ),
        Rule(
            "dart-pub-cache", "Dart & Flutter packages", .packages, .caution,
            summary: "Packages downloaded by flutter pub get and dart pub get.",
            aftermath: "Projects won't build until you run flutter pub get in them again.",
            locations: [.item("~/.pub-cache/hosted"), .item("~/.pub-cache/git")]
        ),
        Rule(
            "go-build-cache", "Go build cache", .packages, .safe,
            summary: "Compiled Go packages.",
            aftermath: "Go recompiles what it needs on the next build.",
            locations: [.item("~/Library/Caches/go-build")]
        ),
        Rule(
            "go-module-cache", "Go module cache", .packages, .caution,
            summary: "Go modules downloaded for your projects.",
            aftermath: "Go downloads modules again on the next build.",
            locations: [.item("~/go/pkg/mod")],
            cleanup: .command("go clean -modcache"),
            note: "Go makes these folders read-only, so they couldn't be emptied from the Trash. Let Go remove them."
        ),
        Rule(
            "cargo-cache", "Cargo registry", .packages, .safe,
            summary: "Crates and git checkouts downloaded by Cargo.",
            aftermath: "Cargo downloads them again on the next build.",
            locations: [
                .item("~/.cargo/registry/cache"), .item("~/.cargo/registry/src"), .item("~/.cargo/git/checkouts"),
            ]
        ),
        Rule(
            "nuget-packages", "NuGet packages", .packages, .caution,
            summary: "NuGet packages downloaded for .NET projects.",
            aftermath: "Restored on the next dotnet restore or build.",
            locations: [.item("~/.nuget/packages")]
        ),
        Rule(
            "composer-cache", "Composer cache", .packages, .safe,
            summary: "PHP packages cached by Composer.",
            aftermath: "Composer downloads them again when needed.",
            locations: [.item("~/Library/Caches/composer"), .item("~/.composer/cache"), .item("~/.cache/composer")]
        ),
        Rule(
            "deno-cache", "Deno cache", .packages, .safe,
            summary: "Modules downloaded and compiled by Deno.",
            aftermath: "Deno downloads them again when needed.",
            locations: [.item("~/Library/Caches/deno")]
        ),
        Rule(
            "node-gyp-cache", "node-gyp headers", .packages, .safe,
            summary: "Node.js headers downloaded to compile native modules.",
            aftermath: "Downloaded again the next time a native module compiles.",
            locations: [.item("~/Library/Caches/node-gyp"), .item("~/.node-gyp")]
        ),
        Rule(
            "electron-downloads", "Electron downloads", .packages, .safe,
            summary: "Electron binaries downloaded by electron and electron-builder.",
            aftermath: "Downloaded again on the next install or build.",
            locations: [.item("~/Library/Caches/electron"), .item("~/Library/Caches/electron-builder")]
        ),
        Rule(
            "test-browsers", "Test browsers", .packages, .caution,
            summary: "Browsers downloaded by Playwright and Puppeteer for automated testing.",
            aftermath: "Run npx playwright install (or reinstall Puppeteer) to get them back.",
            locations: [.item("~/Library/Caches/ms-playwright"), .item("~/.cache/puppeteer")]
        ),
        Rule(
            "jetbrains-caches", "IDE caches", .packages, .safe,
            summary: "Indexes and caches of JetBrains IDEs and Android Studio.",
            aftermath: "The IDE re-indexes your projects the next time you open them.",
            locations: [.item("~/Library/Caches/JetBrains"), .item("~/Library/Caches/Google/AndroidStudio*")],
            note: "Quit your JetBrains IDE or Android Studio first."
        ),
    ]

    // MARK: - Build artifacts inside projects

    static let projects: [Rule] = [
        Rule(
            "node-modules", "node_modules", .projects, .caution,
            summary: "Installed JavaScript dependencies inside your projects.",
            aftermath: "Run npm install (or pnpm, yarn, bun install) in a project to bring them back.",
            discovery: .projects(ArtifactKind(folders: ["node_modules"], markers: ["package.json"]))
        ),
        Rule(
            "js-build-caches", "JavaScript build caches", .projects, .safe,
            summary: "Build output and caches of Next.js, Nuxt, SvelteKit, Turborepo, Parcel and Angular.",
            aftermath: "Recreated on the next dev server start or build.",
            discovery: .projects(ArtifactKind(
                folders: [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular"],
                markers: ["package.json"]
            ))
        ),
        Rule(
            "flutter-build", "Flutter build output", .projects, .safe,
            summary: "What flutter clean removes: build/ and .dart_tool/ in Flutter and Dart projects.",
            aftermath: "Recreated on the next flutter run or build (the first one takes longer).",
            discovery: .projects(ArtifactKind(folders: ["build", ".dart_tool"], markers: ["pubspec.yaml"]))
        ),
        Rule(
            "gradle-build", "Gradle build output", .projects, .safe,
            summary: "build/ and .gradle/ folders in Android, Kotlin and Java projects.",
            aftermath: "Recreated on the next Gradle build.",
            discovery: .projects(ArtifactKind(
                folders: ["build", ".gradle"],
                markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
            ))
        ),
        Rule(
            "target-folders", "Rust & Maven build output", .projects, .safe,
            summary: "target/ folders in Cargo and Maven projects.",
            aftermath: "Recreated on the next cargo build or mvn package.",
            discovery: .projects(ArtifactKind(folders: ["target"], markers: ["Cargo.toml", "pom.xml"]))
        ),
        Rule(
            "swiftpm-build", "Swift package builds", .projects, .safe,
            summary: ".build/ folders in Swift packages.",
            aftermath: "Recreated on the next swift build.",
            discovery: .projects(ArtifactKind(folders: [".build"], markers: ["Package.swift"]))
        ),
        Rule(
            "cocoapods-pods", "CocoaPods Pods", .projects, .caution,
            summary: "Pods/ folders installed by CocoaPods in iOS projects.",
            aftermath: "Run pod install (or flutter build ios) to bring them back.",
            discovery: .projects(ArtifactKind(folders: ["Pods"], markers: ["Podfile"]))
        ),
        Rule(
            "python-venvs", "Python virtual environments", .projects, .review,
            summary: "Virtual environments inside your projects.",
            aftermath: "Recreate one with python3 -m venv and reinstall its packages, e.g. pip install -r requirements.txt.",
            discovery: .projects(ArtifactKind(folders: [], innerMarker: "pyvenv.cfg"))
        ),
    ]

    // MARK: - SDKs & toolchains

    static let toolchains: [Rule] = [
        Rule(
            "arduino-staging", "Arduino downloads", .toolchains, .safe,
            summary: "Archives the Arduino IDE downloaded and already installed.",
            aftermath: "Nothing. They're only needed during installation.",
            locations: [.item("~/Library/Arduino15/staging")]
        ),
        Rule(
            "platformio-cache", "PlatformIO cache", .toolchains, .safe,
            summary: "Downloads cached by PlatformIO.",
            aftermath: "Downloaded again when needed.",
            locations: [.item("~/.platformio/.cache")]
        ),
        Rule(
            "android-system-images", "Android system images", .toolchains, .review,
            summary: "Emulator system images, one folder per Android version.",
            aftermath: "Emulators built on a removed image stop working. Reinstall images from Android Studio → SDK Manager.",
            locations: [.children("~/Library/Android/sdk/system-images")]
        ),
        Rule(
            "android-emulators", "Android emulators", .toolchains, .review,
            summary: "Virtual devices you created in Android Studio, with their disks and snapshots.",
            aftermath: "The emulator and everything installed on it is gone.",
            locations: [.children("~/.android/avd", matching: ["*.avd"])],
            cleanup: .manual("Android Studio → Device Manager → ⋮ → Delete")
        ),
        Rule(
            "android-ndk", "Android NDK versions", .toolchains, .review,
            summary: "Native Development Kit versions, often several side by side.",
            aftermath: "A project that pins a removed version downloads it again on its next build.",
            locations: [.children("~/Library/Android/sdk/ndk")]
        ),
        Rule(
            "arduino-packages", "Arduino board packages", .toolchains, .review,
            summary: "Board support and compiler toolchains installed by the Arduino IDE. ESP32 alone takes about 5 GB.",
            aftermath: "Reinstall a board from Arduino IDE → Boards Manager when you need it.",
            locations: [.children("~/Library/Arduino15/packages")],
            quitFirst: ["Arduino IDE"]
        ),
    ]

    // MARK: - VMs & containers

    static let virtualization: [Rule] = [
        Rule(
            "docker-desktop", "Docker Desktop disk", .virtualization, .review,
            summary: "Docker Desktop's virtual disk: your images, containers, volumes and build cache.",
            aftermath: "The command removes stopped containers, unused images and build cache. Volumes stay.",
            locations: [.item("~/Library/Containers/com.docker.docker/Data/vms/0/data")],
            cleanup: .command("docker system prune -a"),
            note: "The disk image doesn't shrink right away; Docker Desktop gives the space back in the background."
        ),
        Rule(
            "colima", "Colima VM", .virtualization, .review,
            summary: "The Linux VM Colima runs Docker in, with all your images and containers.",
            aftermath: "The command removes unused images and containers. colima delete removes the whole VM.",
            locations: [.item("~/.colima/_lima")],
            cleanup: .command("docker system prune -a")
        ),
        Rule(
            "orbstack", "OrbStack data", .virtualization, .review,
            summary: "OrbStack's disk with your containers, images and Linux machines.",
            aftermath: "The command removes stopped containers and unused images.",
            locations: [.item("~/Library/Group Containers/*.dev.orbstack/data")],
            cleanup: .command("docker system prune -a")
        ),
        Rule(
            "claude-vm", "Claude desktop VM", .virtualization, .review,
            summary: "The Linux VM the Claude desktop app uses for its agent features.",
            aftermath: "Claude downloads it again (about 10 GB) the next time a feature needs it.",
            locations: [.item("~/Library/Application Support/Claude/vm_bundles")],
            quitFirst: ["Claude"]
        ),
        Rule(
            "crossover-bottles", "CrossOver bottles", .virtualization, .review,
            summary: "Windows apps installed with CrossOver, one bottle each.",
            aftermath: "The Windows apps in a bottle and their data are gone.",
            locations: [.children("~/Library/Application Support/CrossOver/Bottles")],
            quitFirst: ["CrossOver"]
        ),
        Rule(
            "parallels-vms", "Parallels VMs", .virtualization, .review,
            summary: "Virtual machines stored in ~/Parallels.",
            aftermath: "The VM and everything in it is gone.",
            locations: [.children("~/Parallels", matching: ["*.pvm"])],
            quitFirst: ["Parallels Desktop"]
        ),
        Rule(
            "utm-vms", "UTM VMs", .virtualization, .review,
            summary: "Virtual machines created in UTM.",
            aftermath: "The VM and everything in it is gone.",
            locations: [.children("~/Library/Containers/com.utmapp.UTM/Data/Documents", matching: ["*.utm"])],
            quitFirst: ["UTM"]
        ),
        Rule(
            "vagrant-boxes", "Vagrant boxes", .virtualization, .caution,
            summary: "Base box images downloaded by Vagrant.",
            aftermath: "Downloaded again on the next vagrant up that needs them.",
            locations: [.children("~/.vagrant.d/boxes")]
        ),
    ]

    // MARK: - AI models

    static let aiModels: [Rule] = [
        Rule(
            "huggingface-cache", "Hugging Face cache", .aiModels, .caution,
            summary: "Models and datasets downloaded by transformers, diffusers and other Hugging Face libraries.",
            aftermath: "Downloaded again the next time your code asks for them.",
            locations: [.children("~/.cache/huggingface/hub", matching: ["models--*", "datasets--*", "spaces--*"])]
        ),
        Rule(
            "ollama-models", "Ollama models", .aiModels, .review,
            summary: "Local language models downloaded with Ollama.",
            aftermath: "Pull a model again with ollama pull when you need it.",
            locations: [.item("~/.ollama/models")],
            cleanup: .command("ollama list   # then: ollama rm <model>")
        ),
        Rule(
            "lmstudio-models", "LM Studio models", .aiModels, .review,
            summary: "Models downloaded in LM Studio, grouped by publisher.",
            aftermath: "Download them again from LM Studio's model search.",
            locations: [.children("~/.lmstudio/models"), .children("~/.cache/lm-studio/models")],
            quitFirst: ["LM Studio"]
        ),
    ]

    // MARK: - Apps

    static let applications: [Rule] = [
        Rule(
            "large-apps", "Large apps", .applications, .review,
            summary: "Apps over 500 MB in your Applications folders, with when you last opened each.",
            aftermath: "Moving an app to the Trash uninstalls it. Its settings and data in ~/Library stay behind.",
            discovery: .applications
        ),
    ]

    // MARK: - Downloads & backups

    static let files: [Rule] = [
        Rule(
            "device-updates", "iOS update files", .files, .safe,
            summary: "iOS and iPadOS firmware Finder downloaded to update or restore devices.",
            aftermath: "Finder downloads it again the next time it's needed.",
            locations: [
                .children("~/Library/iTunes/iPhone Software Updates"),
                .children("~/Library/iTunes/iPad Software Updates"),
            ]
        ),
        Rule(
            "mail-downloads", "Opened Mail attachments", .files, .safe,
            summary: "Copies of attachments you opened from Mail. The originals stay in your mailboxes.",
            aftermath: "Nothing. Mail makes a new copy when you open an attachment again.",
            locations: [.item("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
            quitFirst: ["Mail"]
        ),
        Rule(
            "old-installers", "Installers in Downloads", .files, .review,
            summary: "Disk images and installer packages in Downloads that are more than a week old.",
            aftermath: "You'll have to download an installer again to reinstall from it.",
            locations: [
                .children("~/Downloads", matching: ["*.dmg", "*.pkg", "*.mpkg", "*.iso", "*.xip"], olderThanDays: 7),
            ]
        ),
        Rule(
            "device-backups", "iPhone & iPad backups", .files, .review,
            summary: "Local device backups made by Finder.",
            aftermath: "Gone for good once you empty the Trash. Make sure you have a newer backup, or iCloud Backup, first.",
            locations: [.children("~/Library/Application Support/MobileSync/Backup")],
            discovery: .deviceBackups
        ),
        Rule(
            "messages-attachments", "Messages attachments", .files, .review,
            summary: "Photos, videos and files from your conversations in Messages.",
            aftermath: "Removing them from Messages deletes them from those conversations.",
            locations: [.item("~/Library/Messages/Attachments")],
            cleanup: .manual("System Settings → General → Storage → Messages")
        ),
    ]
}
