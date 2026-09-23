import DustpanCore
import Foundation

let usage = """
\(Style.bold("dustpan")) \(Dustpan.version): see what's filling your Mac, then sweep it into the Trash.

\(Style.bold("USAGE"))
  dustpan [scan]                 Show what's taking space (the default)
  dustpan clean <id>... [flags]  Move what those rules found to the Trash
  dustpan rules                  List every rule Dustpan knows
  dustpan help | --version

\(Style.bold("SCAN"))
  --all                 List every item inside each finding
  --json                Machine-readable output
  --roots <dir,dir>     Where to look for build folders like node_modules
                        (default: ~/Desktop, ~/Documents, ~/Developer, ~/Code…)

\(Style.bold("CLEAN"))
  --safe                Everything marked SAFE
  --older-than <days>   Only items untouched for this many days
  --dry-run             Show what would move, move nothing
  -y, --yes             Don't ask for confirmation

\(Style.bold("RULES"))
  --markdown            Print the rules as a Markdown table

Dustpan never deletes anything. It moves things to the Trash; you empty it when you're sure.
"""

// MARK: - Argument parsing

var arguments = Array(CommandLine.arguments.dropFirst())

@MainActor func takeFlag(_ names: String...) -> Bool {
    guard let index = arguments.firstIndex(where: names.contains) else { return false }
    arguments.remove(at: index)
    return true
}

@MainActor func takeOption(_ name: String) -> String? {
    if let index = arguments.firstIndex(where: { $0.hasPrefix(name + "=") }) {
        return String(arguments.remove(at: index).dropFirst(name.count + 1))
    }
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else {
        printError("\(name) needs a value.")
        exit(64)
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

@MainActor func rejectLeftovers() {
    if let unknown = arguments.first(where: { $0.hasPrefix("-") }) {
        printError("unknown option \(unknown). See dustpan help.")
        exit(64)
    }
}

func expandPath(_ path: String) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded).standardizedFileURL
}

if takeFlag("--no-color") { Style.enabled = false }
let command = arguments.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "scan"
if !arguments.isEmpty && !arguments[0].hasPrefix("-") { arguments.removeFirst() }

// MARK: - Commands

switch command {
case "help", "-h", "--help":
    print(usage)
case "version":
    print(Dustpan.version)
case "scan":
    if takeFlag("-h", "--help") { print(usage); exit(0) }
    if takeFlag("--version") { print(Dustpan.version); exit(0) }
    await runScan()
case "clean":
    await runClean()
case "rules":
    runRules()
default:
    printError("unknown command \(command). See dustpan help.")
    exit(64)
}

// MARK: scan

@MainActor func scanOptions(ruleIDs: Set<String>? = nil) -> ScanOptions {
    let roots = takeOption("--roots").map { $0.split(separator: ",").map { expandPath(String($0)) } }
    return ScanOptions(projectRoots: roots, ruleIDs: ruleIDs)
}

@MainActor func runScan() async {
    let showAll = takeFlag("--all")
    let json = takeFlag("--json")
    let options = scanOptions()
    rejectLeftovers()
    if !arguments.isEmpty {
        printError("scan takes no arguments. Did you mean dustpan clean \(arguments.joined(separator: " "))?")
        exit(64)
    }

    let line = ProgressLine()
    let report = await Scanner(options: options).scan { line.update($0) }
    line.clear()

    if json {
        print(JSONReport(report).encoded())
    } else {
        printReport(report, showAll: showAll, roots: options.projectRoots)
    }
}

func printReport(_ report: ScanReport, showAll: Bool, roots: [URL]) {
    let idWidth = min(24, (report.findings.map(\.rule.id.count).max() ?? 10) + 2)
    let nameWidth = 36
    let sizeWidth = 9

    print()
    if let disk = report.disk {
        var free = "\(Format.bytes(disk.available)) free"
        if disk.purgeable > 1_000_000_000 { free += " (+\(Format.bytes(disk.purgeable)) purgeable)" }
        print(" \(Style.bold(disk.volumeName))  \(diskBar(disk.usedFraction))  \(Format.bytes(disk.used)) used of \(Format.bytes(disk.total)) · \(free)")
    }

    func row(_ finding: Finding) -> String {
        let count = finding.targets.count > 1 ? Style.dim(" (\(finding.targets.count))") : ""
        let name = finding.rule.name.truncated(to: nameWidth - 6) + count
        return "   " + Style.cyan(finding.rule.id).padded(to: idWidth) + name.padded(to: nameWidth)
            + Style.bold(Format.bytes(finding.bytes)).leftPadded(to: sizeWidth)
    }

    func items(_ finding: Finding, limit: Int) {
        // A single path with nothing more to say would only repeat the row above it.
        if finding.targets.count == 1 && finding.targets[0].detail == nil && finding.targets[0].command == nil && !showAll { return }
        let shown = showAll ? finding.targets : Array(finding.targets.prefix(limit))
        for target in shown {
            var line = "     " + target.label.truncated(to: idWidth + nameWidth - 8).padded(to: idWidth + nameWidth - 2)
                + Format.bytes(target.bytes).leftPadded(to: sizeWidth)
            if let detail = target.detail { line += "  " + detail }
            print(Style.dim(line))
            if let command = target.command { print("       " + Style.dim("run: ") + command) }
        }
        let hidden = finding.targets.count - shown.count
        if hidden > 0 { print(Style.dim("     … and \(hidden) more (dustpan scan --all)")) }
    }

    let movable = report.findings.filter { !$0.locked && $0.isCleanable }
    for safety in Safety.allCases {
        let group = movable.filter { $0.rule.safety == safety }.sorted { $0.bytes > $1.bytes }
        guard !group.isEmpty else { continue }
        let total = group.reduce(0) { $0 + $1.bytes }
        let title = Style.safety(safety, Style.bold(safety.title.uppercased())) + "  " + Style.dim(safety.explanation.lowercased())
        print()
        print(" " + title.padded(to: idWidth + nameWidth + 2) + Style.bold(Format.bytes(total)).leftPadded(to: sizeWidth))
        for finding in group {
            print(row(finding))
            if safety == .review || showAll { items(finding, limit: 3) }
        }
    }

    let others = report.findings.filter { !$0.locked && !$0.isCleanable }
    if !others.isEmpty {
        print()
        print(" " + Style.bold("CLEAN IT YOURSELF") + "  " + Style.dim("the tool that owns it should do the deleting"))
        for finding in others {
            print(row(finding))
            switch finding.rule.cleanup {
            case .command(let command) where finding.targets.allSatisfy({ $0.command == nil }):
                print("     " + Style.dim("run: ") + command)
            case .manual(let steps):
                print("     " + Style.dim("in: ") + steps)
            default:
                break
            }
            if finding.targets.contains(where: { $0.command != nil }) || showAll { items(finding, limit: 5) }
        }
    }

    if !report.lockedFindings.isEmpty {
        print()
        print(" " + Style.bold("LOCKED") + "  " + Style.dim("macOS hides these until your terminal has Full Disk Access"))
        let names = report.lockedFindings.map(\.rule.name).joined(separator: " · ")
        print("   " + names)
        print("   " + Style.dim("System Settings › Privacy & Security › Full Disk Access › add your terminal app"))
    }

    let safe = report.cleanableBytes(.safe)
    let caution = report.cleanableBytes(.caution)
    let review = report.cleanableBytes(.review)
    let otherBytes = others.reduce(0) { $0 + $1.bytes }
    print()
    print(" " + Style.bold(Format.bytes(safe + caution)) + " of caches and build output comes back on its own ("
        + Style.green("\(Format.bytes(safe)) safe") + " · " + Style.yellow("\(Format.bytes(caution)) caution") + ").")
    if review + otherBytes > 0 {
        print(" " + Style.magenta(Format.bytes(review)) + " more is yours to review, and \(Format.bytes(otherBytes)) is best cleaned by its own tool.")
    }
    if let trash = report.trashBytes, trash > 0 {
        print(" The Trash already holds \(Format.bytes(trash)); empty it in Finder to get that space back.")
    }
    let rootList = roots.map { Format.path($0) }.joined(separator: ", ")
    print(Style.dim(" Looked for build folders in \(rootList.isEmpty ? "no folders" : rootList). Scanned in \(String(format: "%.1f", report.duration)) s."))
    print()
    var suggestions: [(String, String)] = []
    if safe > 0 {
        suggestions.append(("dustpan clean --safe", "move the \(Format.bytes(safe)) marked SAFE to the Trash"))
    }
    let biggest = movable.filter { $0.rule.safety == .safe }.sorted { $0.bytes > $1.bytes }.prefix(2).map(\.rule.id)
    if !biggest.isEmpty {
        suggestions.append(("dustpan clean \(biggest.joined(separator: " "))", "or pick by id"))
    }
    let width = (suggestions.map(\.0.count).max() ?? 0) + 3
    for (command, note) in suggestions {
        print(" " + command.padded(to: width) + Style.dim(note))
    }
    print(Style.dim(" Nothing is deleted: items go to the Trash, and you empty it when you're sure."))
    print()
}

// MARK: clean

@MainActor func runClean() async {
    let dryRun = takeFlag("--dry-run", "-n")
    let assumeYes = takeFlag("--yes", "-y")
    let safeOnly = takeFlag("--safe")
    let olderThan = takeOption("--older-than").map { value -> Int in
        guard let days = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "d"))), days >= 0 else {
            printError("--older-than takes a number of days, e.g. --older-than 30")
            exit(64)
        }
        return days
    }
    let rootsOption = takeOption("--roots")
    rejectLeftovers()

    var ids = arguments
    if safeOnly {
        ids += Catalog.rules.filter { $0.safety == .safe && $0.cleanup.isTrash }.map(\.id)
    }
    guard !ids.isEmpty else {
        printError("tell me what to clean: rule ids from dustpan scan, or --safe.")
        exit(64)
    }
    for id in ids where Catalog.rule(id: id) == nil {
        let guesses = Catalog.rules.map(\.id).filter { $0.contains(id) || id.contains($0) }
        printError("no rule called \(id)." + (guesses.isEmpty ? " See dustpan rules." : " Did you mean \(guesses.joined(separator: ", "))?"))
        exit(64)
    }

    let roots = rootsOption.map { $0.split(separator: ",").map { expandPath(String($0)) } }
    let options = ScanOptions(projectRoots: roots, ruleIDs: Set(ids))
    let line = ProgressLine()
    let report = await Scanner(options: options).scan { line.update($0) }
    line.clear()

    let cutoff = olderThan.map { Date().addingTimeInterval(-Double($0) * 86_400) }
    var chosen: [Target] = []
    var quit = Set<String>()
    print()
    for finding in report.findings {
        if finding.locked {
            print(" " + Style.dim("\(finding.rule.name): locked, needs Full Disk Access."))
            continue
        }
        guard finding.isCleanable else {
            switch finding.rule.cleanup {
            case .command(let command):
                print(" \(finding.rule.name): Dustpan leaves this to its own tool. Run: \(Style.bold(command))")
            case .manual(let steps):
                print(" \(finding.rule.name): clean it in \(steps).")
            case .trash:
                break
            }
            continue
        }
        let targets = finding.targets.filter { target in
            guard let cutoff else { return true }
            return (target.modified ?? .distantFuture) < cutoff
        }
        guard !targets.isEmpty else { continue }
        chosen += targets
        quit.formUnion(finding.rule.quitFirst)
        let size = Format.bytes(targets.reduce(0) { $0 + $1.bytes })
        print(" " + Style.safety(finding.rule.safety, "●") + " " + finding.rule.name.padded(to: 38) + Style.bold(size).leftPadded(to: 9)
            + Style.dim("  \(targets.count) item\(targets.count == 1 ? "" : "s")"))
        for target in targets.prefix(dryRun ? .max : 4) {
            print(Style.dim("     " + Format.path(target.url)))
        }
        if !dryRun && targets.count > 4 { print(Style.dim("     … and \(targets.count - 4) more")) }
    }

    let total = chosen.reduce(0) { $0 + $1.bytes }
    guard !chosen.isEmpty else {
        print(" Nothing to move.\n")
        return
    }
    print()
    if !quit.isEmpty {
        print(" " + Style.yellow("Quit first: ") + quit.sorted().joined(separator: ", "))
    }
    if dryRun {
        print(" Dry run: \(chosen.count) items, \(Format.bytes(total)). Nothing was moved.\n")
        return
    }
    if !assumeYes {
        guard isatty(STDIN_FILENO) == 1 else {
            printError("not a terminal, so I can't ask. Pass --yes to confirm.")
            exit(1)
        }
        print(" Move \(chosen.count) items (\(Style.bold(Format.bytes(total)))) to the Trash? [y/N] ", terminator: "")
        guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
            print(" Nothing moved.\n")
            return
        }
    }

    let result = Cleaner().clean(chosen)
    print()
    print(" " + Style.green("Moved \(result.moved.count) items (\(Format.bytes(result.movedBytes))) to the Trash."))
    for failure in result.failures {
        print(" " + Style.red("✗ ") + Format.path(failure.target.url) + Style.dim(": " + failure.reason))
    }
    if result.movedBytes > 0 {
        print(" Empty the Trash when you're sure, and the space is yours again.")
    }
    print()
}

// MARK: rules

@MainActor func runRules() {
    let markdown = takeFlag("--markdown")
    rejectLeftovers()
    if markdown {
        print("| Rule | What it finds | Safety | Cleanup |")
        print("| --- | --- | --- | --- |")
        for category in Category.allCases {
            print("| **\(category.title)** | | | |")
            for rule in Catalog.rules where rule.category == category {
                let cleanup: String
                switch rule.cleanup {
                case .trash: cleanup = "Trash"
                case .command(let command): cleanup = "`\(command.replacingOccurrences(of: "|", with: "\\|"))`"
                case .manual(let steps): cleanup = steps
                }
                print("| `\(rule.id)` | \(rule.summary) | \(rule.safety.title) | \(cleanup) |")
            }
        }
        return
    }
    for category in Category.allCases {
        print()
        print(" " + Style.bold(category.title))
        for rule in Catalog.rules where rule.category == category {
            let cleanup: String
            switch rule.cleanup {
            case .trash: cleanup = ""
            case .command(let command): cleanup = Style.dim("  run: \(command)")
            case .manual(let steps): cleanup = Style.dim("  in: \(steps)")
            }
            print("   " + Style.cyan(rule.id).padded(to: 26) + Style.safety(rule.safety, rule.safety.title.uppercased()).padded(to: 9) + rule.name + cleanup)
        }
    }
    print()
    print(Style.dim(" \(Catalog.rules.count) rules. Details for each: dustpan scan --all"))
    print()
}
