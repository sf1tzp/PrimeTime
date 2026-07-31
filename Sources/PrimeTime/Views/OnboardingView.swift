import SwiftUI
import PrimeTimeCore

/// The first-run sequence (issue #93): Welcome (optionally connect a sync
/// server or import from Traggo) → interactive walkthrough of the label model
/// (skippable) → pick starter label sets → land in the Label Sets tab.
/// Hosted by `OnboardingWindowManager`; the walkthrough step itself lives in
/// `WalkthroughView` with `WalkthroughModel` as its shared dataset.
struct OnboardingView: View {
    /// One shared fixed size — the window never resizes between steps.
    static let size = CGSize(width: 700, height: 560)

    private enum Step {
        case welcome, walkthrough, starterSets
    }

    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome
    @State private var walkthrough = WalkthroughModel()

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeStep(onContinue: { step = .walkthrough })
            case .walkthrough:
                WalkthroughView(
                    walkthrough: walkthrough,
                    onBack: { step = .welcome },
                    onContinue: { step = .starterSets })
            case .starterSets:
                StarterSetsStep(onBack: { step = .walkthrough })
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The window is .fullSizeContentView, so pad the top edge clear of
        // the floating traffic lights.
        .background(.background)
    }
}

// MARK: - Shared chrome

/// The fixed bottom bar every step ends with: optional Back, optional
/// secondary action, one prominent primary action.
struct OnboardingFooter<Secondary: View>: View {
    var back: (() -> Void)?
    var primaryTitle: String
    var primaryAction: () -> Void
    @ViewBuilder var secondary: Secondary

    var body: some View {
        HStack {
            if let back {
                Button("Back", action: back)
            }
            Spacer()
            secondary
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(20)
    }
}

extension OnboardingFooter where Secondary == EmptyView {
    init(back: (() -> Void)? = nil, primaryTitle: String,
         primaryAction: @escaping () -> Void) {
        self.init(back: back, primaryTitle: primaryTitle,
                  primaryAction: primaryAction) { EmptyView() }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @Environment(AppModel.self) private var model
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.top, 48)
                    Text("Welcome to PrimeTime")
                        .font(.largeTitle.weight(.semibold))
                    Text("A menu-bar time tracker where labels do the organising — no folders, no projects tree, just spans and their key: value labels.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    VStack(spacing: 10) {
                        if model.isDemo {
                            Label("Demo mode — running on seeded sample data; connections are disabled.",
                                  systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            SyncConnectCard()
                            TraggoImportCard()
                            Text("Both are optional and live in Settings whenever you want them — everything works locally out of the box.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: 460)
                    .padding(.top, 24)
                }
                .frame(maxWidth: .infinity)
            }
            Divider()
            OnboardingFooter(primaryTitle: "Continue", primaryAction: onContinue)
        }
    }
}

/// Compact welcome-flavoured version of Settings' sync section: same model
/// calls, disclosure instead of a form.
private struct SyncConnectCard: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        WelcomeActionCard(symbol: "arrow.triangle.2.circlepath",
                          title: "Connect to a PrimeTime server",
                          subtitle: "Sync spans, labels, and colours across your Macs.",
                          expanded: $expanded) {
            if let server = model.syncServer {
                Label("Connected to \(server.url)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                TextField("Server URL", text: $url)
                    .autocorrectionDisabled()
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .onSubmit(connect)
                HStack {
                    if model.isConnectingSync { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Connect", action: connect)
                        .disabled(url.isEmpty || username.isEmpty || password.isEmpty
                            || model.isConnectingSync)
                }
                if let error = model.syncConnectError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
        }
    }

    private func connect() {
        guard !url.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        Task {
            await model.connectSyncServer(url: url, username: username, password: password)
            password = ""   // never keep the password around
        }
    }
}

/// Compact welcome-flavoured version of Settings' Traggo import section.
private struct TraggoImportCard: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        @Bindable var model = model
        WelcomeActionCard(symbol: "square.and.arrow.down",
                          title: "Import from a Traggo server",
                          subtitle: "Copy a Traggo history — spans, tag keys, colours — into the local database.",
                          expanded: $expanded) {
            TextField("Server URL", text: $model.serverURL)
                .autocorrectionDisabled()
            if model.hasTraggoSession {
                Text("Using the saved Traggo sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            HStack {
                if model.isImporting {
                    ProgressView().controlSize(.small)
                    Text("Imported \(model.importedSpanCount) timespans…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import", action: runImport)
                    .disabled(model.isImporting
                        || (!model.hasTraggoSession && (username.isEmpty || password.isEmpty)))
            }
            if let summary = model.importSummary {
                Label("Imported \(summary.spansImported) timespans and \(summary.definitionsCreated + summary.definitionsRecolored) label keys.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.importError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
    }

    private func runImport() {
        Task {
            await model.importFromTraggo(username: username, password: password)
            password = ""   // never keep the password around
        }
    }
}

/// One optional setup row on the welcome step: an icon + title row that
/// discloses its form when clicked, in the style of app welcome screens.
private struct WelcomeActionCard<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.medium))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content }
                    .padding(.leading, 40)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Step 3: Starter label sets

/// A curated label set offered at the end of onboarding. Deliberately all
/// `type:`-keyed: a small, stable vocabulary — exactly what the walkthrough
/// just preached.
struct StarterTagSet: Identifiable {
    let name: String
    let symbol: String
    let tags: [TagRow]
    var id: String { name }

    static let all: [StarterTagSet] = [
        StarterTagSet(name: "Deep Work", symbol: "brain",
                      tags: [TagRow(key: "type", value: "programming")]),
        StarterTagSet(name: "Meeting", symbol: "person.2",
                      tags: [TagRow(key: "type", value: "meeting")]),
        StarterTagSet(name: "Email & Admin", symbol: "envelope",
                      tags: [TagRow(key: "type", value: "email")]),
        StarterTagSet(name: "Code Review", symbol: "doc.text",
                      tags: [TagRow(key: "type", value: "review")]),
        StarterTagSet(name: "Reading", symbol: "book",
                      tags: [TagRow(key: "type", value: "reading")]),
        StarterTagSet(name: "Workout", symbol: "figure.run",
                      tags: [TagRow(key: "type", value: "workout")]),
    ]
}

private struct StarterSetsStep: View {
    @Environment(AppModel.self) private var model
    var onBack: () -> Void
    @State private var selected: Set<String> = ["Deep Work", "Meeting", "Email & Admin"]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Start with a few label sets")
                    .font(.title.weight(.semibold))
                    .padding(.top, 44)
                Text("A label set is a one-click timer: click it in the menu bar and a span starts with those labels. Pick any that fit — they're yours to edit next.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(.bottom, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(StarterTagSet.all) { set in
                    card(for: set)
                }
            }
            .frame(maxWidth: 520)

            Text("Every set is just labels. In the Label Sets tab you can add the keys you'll query by — repo, client, whatever your charts should group on.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 16)

            Spacer()
            Divider()
            OnboardingFooter(back: onBack,
                             primaryTitle: primaryTitle,
                             primaryAction: finish)
        }
    }

    private var primaryTitle: String {
        selected.isEmpty ? "Finish"
            : "Add \(selected.count) and finish"
    }

    private func card(for set: StarterTagSet) -> some View {
        let isSelected = selected.contains(set.id)
        return Button {
            if isSelected { selected.remove(set.id) } else { selected.insert(set.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: set.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(set.name).font(.body.weight(.medium))
                    // The set's labels, in walkthrough colours — the user's
                    // palette doesn't know these keys yet.
                    HStack(spacing: 4) {
                        ForEach(set.tags) { tag in
                            TagPill(key: tag.key, value: tag.value,
                                    color: WalkthroughModel.keyColor(tag.key))
                        }
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint)
                                                : AnyShapeStyle(.quaternary))
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
    }

    /// Append the picked sets (skipping any name the user already has, e.g.
    /// demo seeds), then close the window and open the Label Sets tab so the
    /// user lands next to what they just created.
    private func finish() {
        let existing = Set(model.tagSets.map { $0.name.lowercased() })
        for starter in StarterTagSet.all
        where selected.contains(starter.id) && !existing.contains(starter.name.lowercased()) {
            model.tagSets.append(TagSet(name: starter.name, tags: starter.tags,
                                        symbolName: starter.symbol))
        }
        OnboardingWindowManager.shared.finish(openingTagSets: true)
    }
}
