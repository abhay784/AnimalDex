import SwiftUI
import SwiftData

/// The landing screen: a live viewfinder with the detection banner and shutter.
struct ScannerView: View {
    @Bindable var model: ScannerViewModel
    @Environment(\.modelContext) private var context
    @Environment(SpeciesCatalog.self) private var catalog

    @State private var location = LocationProvider()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            CameraPreviewView(source: model.source)
                .ignoresSafeArea(edges: .horizontal)
                .onTapGesture { model.cycleSample() }

            reticle
            VStack {
                banner
                Spacer()
                shutterRow
            }
            .padding(.vertical, 14)

            if let message = model.errorMessage {
                toast(message)
            }
        }
        .background(Theme.outline)
        .task {
            // Deliberately does NOT ask for location here. Prompting the instant
            // the app opens gives the user no context for why, at the moment
            // they are least likely to agree. Location is opted into from the
            // Trainer tab instead, and a catch without it is still a good catch.
            await model.start()
        }
        .onDisappear { model.stop() }
        .fullScreenCover(item: $model.pendingCatch) { pending in
            CatchSequenceView(pending: pending, location: location)
        }
    }

    // MARK: - Reticle

    private var reticle: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.68
            let color = lockColor
            ZStack {
                ForEach(0..<4, id: \.self) { corner in
                    ReticleCorner()
                        .stroke(color, style: .init(lineWidth: 5, lineCap: .round))
                        // Dark underlay so the bracket reads against a bright
                        // subject - white-on-sunlit-wing is invisible otherwise.
                        .background(
                            ReticleCorner()
                                .stroke(Theme.outline.opacity(0.65), style: .init(lineWidth: 9, lineCap: .round))
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(Double(corner) * 90))
                        .offset(
                            x: (corner == 1 || corner == 2 ? 1 : -1) * (side / 2 - 17),
                            y: (corner >= 2 ? 1 : -1) * (side / 2 - 17)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.2), value: lockColor)
        }
        .allowsHitTesting(false)
    }

    private var lockColor: Color {
        switch model.gateState {
        case .idle:     return .white.opacity(0.55)
        case .sensing:  return Theme.ledYellow
        case .locked:   return model.lockedSpecies?.rarity.color ?? Theme.ledGreen
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        switch model.gateState {
        case .idle:
            EmptyView()
        case .sensing:
            capsuleBanner(
                text: "SOMETHING'S OUT THERE… GET CLOSER",
                tint: Theme.ledYellow
            )
        case .locked:
            if let species = model.lockedSpecies {
                VStack(spacing: 7) {
                    capsuleBanner(
                        text: "A WILD \(species.commonName.uppercased()) APPEARED!",
                        tint: species.rarity.color
                    )
                    HStack(spacing: 6) {
                        TypeBadge(type: species.taxonType, compact: true)
                        RarityChip(rarity: species.rarity, compact: true)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func capsuleBanner(text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.display(13))
            .tracking(0.8)
            .multilineTextAlignment(.center)
            .outlinedText()
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Theme.outline.opacity(0.88))
            )
            .overlay(Capsule().strokeBorder(tint, lineWidth: 3))
            .shadow(color: tint.opacity(0.7), radius: 12)
            .padding(.horizontal, 18)
            .accessibilityIdentifier("detectionBanner")
    }

    // MARK: - Shutter

    private var shutterRow: some View {
        Button {
            guard !isCapturing else { return }
            Task {
                isCapturing = true
                SoundBank.shared.play(.throwOrb)
                Haptics.detect()
                await model.captureAndIdentify()
                isCapturing = false
            }
        } label: {
            OrbMark(
                size: 80,
                accent: model.lockedSpecies?.rarity.color ?? Theme.panel
            )
            .scaleEffect(isCapturing ? 0.9 : 1)
            .shadow(color: .black.opacity(0.5), radius: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .animation(.spring(duration: 0.25), value: isCapturing)
        .accessibilityIdentifier("shutter")
        .accessibilityLabel("Capture and identify")
    }

    private func toast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message.uppercased())
                .font(Theme.screenText(11))
                .foregroundStyle(Theme.phosphor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Theme.lcd)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2.5)
                )
                .padding(.bottom, 108)
                .padding(.horizontal, 24)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

/// One L-shaped corner bracket of the reticle.
struct ReticleCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// Small rarity pill used on banners and cards.
struct RarityChip: View {
    let rarity: Rarity
    var compact: Bool = false

    var body: some View {
        Text(rarity.displayName)
            .font(Theme.display(compact ? 9 : 11))
            .tracking(0.8)
            .outlinedText()
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 3 : 5)
            .background(Capsule().fill(rarity.color))
            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 2))
    }
}
