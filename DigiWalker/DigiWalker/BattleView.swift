import DigiWalkerCore
import SwiftUI

struct BattleView: View {
    let snapshot: MonsterSnapshot
    @State private var flow: BattleFlow
    @State private var scanning = false
    @State private var scannedText: String?
    #if DEBUG
    @State private var debugText = ""
    #endif

    init(snapshot: MonsterSnapshot) {
        self.snapshot = snapshot
        _flow = State(initialValue: BattleFlow(snapshot: snapshot))
    }

    var body: some View {
        @Bindable var flow = flow
        List {
            if let blocked = flow.blockedMessage {
                Section {
                    ContentUnavailableView(blocked, systemImage: "egg")
                        .accessibilityIdentifier("battleBlocked")
                }
            } else {
                mySection
                if let card = flow.myCard { qrSection(card) }
                Section {
                    Button("상대 QR 찍기", systemImage: "qrcode.viewfinder") { scanning = true }
                        .accessibilityIdentifier("battleScan")
                    #if DEBUG
                    TextField("(디버그) QR 문자열", text: $debugText).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("붙여넣기로 입력") { flow.handleScanned(debugText) }
                    #endif
                    if let notice = flow.notice {
                        Text(notice).foregroundStyle(.orange).accessibilityIdentifier("battleNotice")
                    }
                }
            }
        }
        .navigationTitle("배틀하기")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: snapshot) { _, new in flow.update(snapshot: new) }
        .sheet(isPresented: $scanning, onDismiss: {
            if let text = scannedText { scannedText = nil; flow.handleScanned(text) }
        }) {
            NavigationStack {
                BattleScannerView { text in scannedText = text; scanning = false }
                    .navigationTitle("상대 QR 찍기").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { scanning = false } } }
            }
        }
        .sheet(item: $flow.pendingPick) { pick in
            NavigationStack {
                BattlePickList(title: "\(StageLabel.text(pick.stage)) 디지몬 고르기", roster: flow.roster,
                               stages: [pick.stage], selected: nil, current: flow.roster.defaultFighter) {
                    flow.startBattle(mine: $0, opponent: pick.opponent)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { flow.pendingPick = nil } } }
            }
        }
        .navigationDestination(isPresented: Binding(get: { flow.encounter != nil },
                                                    set: { if !$0 { flow.encounter = nil } })) {
            BattleArenaView(flow: flow)
        }
    }

    @ViewBuilder private var mySection: some View {
        Section("내 디지몬") {
            if let mine = flow.myFighter {
                HStack(spacing: 12) {
                    PartnerPortrait(speciesId: mine.speciesId, slot: 64, animated: true)
                    VStack(alignment: .leading) {
                        Text(mine.name).font(.headline)
                        Text(StageLabel.text(mine.stage)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("도감에서 내보낼 디지몬을 골라 주세요").foregroundStyle(.secondary)
            }
            NavigationLink("도감에서 바꾸기") {
                BattlePickList(title: "내보낼 디지몬", roster: flow.roster, stages: flow.roster.stages,
                               selected: flow.myFighter, current: flow.roster.defaultFighter) { flow.select($0) }
            }
        }
    }

    private func qrSection(_ card: BattleCard) -> some View {
        Section("내 QR") {
            VStack(spacing: 8) {
                BattleQRView(payload: card.encoded())
                Text("\(card.name) · \(StageLabel.text(card.stage))").font(.subheadline)
                #if DEBUG
                Text(card.encoded()).font(.caption2).textSelection(.enabled).foregroundStyle(.secondary)
                Button("복사") { UIPasteboard.general.string = card.encoded() }
                #endif
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Black and white at a whole-number scale with a four-module quiet zone, in light and dark mode alike.
struct BattleQRView: View {
    let payload: String
    var side: CGFloat = 220

    var body: some View {
        if let cg = BattleQRImage.make(payload) {
            let k = CGFloat(BattleQRImage.scale(modules: cg.width + 8, side: side))
            Image(decorative: cg, scale: 1)
                .interpolation(.none).resizable()
                .frame(width: CGFloat(cg.width) * k, height: CGFloat(cg.height) * k)
                .padding(4 * k)
                .background(Color.white)
                .accessibilityLabel("내 배틀 QR")
        } else {
            Text("QR을 만들 수 없어요").foregroundStyle(.secondary)
        }
    }
}

/// Fighters by stage. Used to change "my fighter" and to match the opponent's stage.
struct BattlePickList: View {
    let title: String
    let roster: BattleRoster
    let stages: [Int]
    let selected: BattleFighter?
    let current: BattleFighter?
    let onSelect: (BattleFighter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(stages, id: \.self) { stage in
                Section(StageLabel.text(stage)) {
                    ForEach(roster.candidates(stage: stage), id: \.speciesId) { fighter in
                        Button {
                            onSelect(fighter)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                PartnerPortrait(speciesId: fighter.speciesId, slot: 48)
                                VStack(alignment: .leading) {
                                    Text(fighter.name).foregroundStyle(.primary)
                                    if fighter == current { Text("지금 키우는 디지몬").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if fighter == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
