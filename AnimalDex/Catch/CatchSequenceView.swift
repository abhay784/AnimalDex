import SwiftUI
import SwiftData

/// The catch. Throw, shake, resolve, register.
///
/// Like the boot sequence, every beat hangs off one `Beat` enum and one `run()`
/// timeline rather than a scatter of booleans and nested animation completions —
/// which is what makes it possible to score the audio and haptics to the visuals
/// instead of guessing at delays.
struct CatchSequenceView: View {
    let pending: PendingCatch
    let location: LocationProvider

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Beat: Int, Comparable {
        case throwing, shaking, caught, registering, resting
        static func < (l: Beat, r: Beat) -> Bool { l.rawValue < r.rawValue }
    }

    @State private var beat: Beat = .throwing
    @State private var orbScale: CGFloat = 1
    @State private var orbOffset: CGFloat = 320
    @State private var flash: Double = 0
    @State private var shakeAngle: Double = 0
    @State private var burst: Double = 0
    @State private var cardScale: CGFloat = 0.2
    @State private var cardOpacity: Double = 0
    @State private var typed: Int = 0
    @State private var isDuplicate = false
    @State private var priorCount = 0

    private var species: Species { pending.species }

    var body: some View {
        ZStack {
            backdrop

            if beat < .caught {
                orb
            }

            if beat >= .caught {
                burstRays
            }

            if beat >= .registering {
                card
            }

            if beat == .resting {
                VStack {
                    Spacer()
                    footer
                }
            }

            Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false)
        }
        .task { await run() }
    }

    // MARK: - Pieces

    private var backdrop: some View {
        ZStack {
            Image(uiImage: pending.image)
                .resizable()
                .scaledToFill()
                .blur(radius: beat >= .caught ? 16 : 4)
                .overlay(Theme.outline.opacity(beat >= .caught ? 0.72 : 0.35))
            RadialGradient(
                colors: [species.rarity.color.opacity(0.45), .clear],
                center: .center, startRadius: 20, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var orb: some View {
        OrbMark(size: 96, accent: species.rarity.color)
            .rotationEffect(.degrees(shakeAngle))
            .scaleEffect(orbScale)
            .offset(y: orbOffset)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
    }

    private var burstRays: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(species.rarity.color.opacity(0.75))
                    .frame(width: 7, height: 150 * burst)
                    .offset(y: -110 * burst)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Circle()
                .stroke(species.rarity.color, lineWidth: 6)
                .frame(width: 260 * burst, height: 260 * burst)
                .opacity(1 - burst)
        }
        .opacity(beat == .resting ? 0.25 : 1)
        .allowsHitTesting(false)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text(isDuplicate ? "ALREADY REGISTERED" : "NEW ENTRY REGISTERED")
                .accessibilityIdentifier("registrationHeadline")
                .font(Theme.display(15))
                .tracking(2)
                .outlinedText(isDuplicate ? Theme.phosphor : Theme.ledYellow)

            DexCardView(
                species: species,
                image: pending.image,
                revealedCharacters: typed
            )
            .frame(maxWidth: 340)

            if isDuplicate {
                Text("×\(priorCount + 1) CAUGHT")
                    .font(Theme.display(13))
                    .outlinedText(Theme.panel)
            }
        }
        .padding(.horizontal, 22)
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
    }

    private var footer: some View {
        Button {
            SoundBank.shared.play(.select)
            dismiss()
        } label: {
            Text("CONTINUE")
                .font(Theme.display(16))
                .tracking(2)
                .outlinedText()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Theme.shell)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("continueButton")
        .padding(.horizontal, 34)
        .padding(.bottom, 44)
    }

    // MARK: - Timeline

    private func run() async {
        priorCount = existingCount()
        isDuplicate = priorCount > 0

        // 1. Throw — the orb arcs in and the world flashes white.
        withAnimation(.timingCurve(0.3, 0.8, 0.4, 1.0, duration: 0.42)) {
            orbOffset = 0
            orbScale = 1.15
        }
        try? await Task.sleep(for: .milliseconds(360))
        withAnimation(.easeOut(duration: 0.09)) { flash = 0.9 }
        withAnimation(.easeIn(duration: 0.28).delay(0.09)) { flash = 0 }
        Haptics.detect()

        // 2. Shake — rarer creatures hold the tension longer.
        beat = .shaking
        withAnimation(.spring(duration: 0.2)) { orbScale = 1.0 }
        for _ in 0..<species.rarity.shakeCount {
            try? await Task.sleep(for: .milliseconds(300))
            SoundBank.shared.play(.shake)
            Haptics.shake()
            withAnimation(.easeInOut(duration: 0.11)) { shakeAngle = -16 }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeInOut(duration: 0.11)) { shakeAngle = 16 }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeInOut(duration: 0.11)) { shakeAngle = 0 }
        }

        // 3. Caught.
        try? await Task.sleep(for: .milliseconds(240))
        beat = .caught
        SoundBank.shared.play(isDuplicate ? .duplicate : .caught)
        Haptics.caught()
        withAnimation(.easeOut(duration: 0.55)) { burst = 1 }

        // 4. Register — persist first, then reveal. Writing before the animation
        //    means an interrupted sequence still keeps the catch.
        persist()

        try? await Task.sleep(for: .milliseconds(420))
        beat = .registering
        SoundBank.shared.play(.registered)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            cardScale = 1
            cardOpacity = 1
        }

        if !isDuplicate, let fanfare = SoundCue.fanfare(for: species.rarity) {
            SoundBank.shared.play(fanfare, after: 0.35)
        }

        // 5. Type the field notes in.
        try? await Task.sleep(for: .milliseconds(420))
        let full = species.dexDescription.count
        while typed < full {
            typed = min(full, typed + 2)
            try? await Task.sleep(for: .milliseconds(12))
        }

        beat = .resting
    }

    // MARK: - Persistence

    private func existingCount() -> Int {
        let key = species.labelKey
        let descriptor = FetchDescriptor<CatchRecord>(
            predicate: #Predicate { $0.speciesKey == key }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    private func persist() {
        Task {
            let coordinate = await location.currentCoordinate()
            do {
                let filename = try PhotoStore.shared.save(pending.image)
                let record = CatchRecord(
                    speciesKey: species.labelKey,
                    coordinate: coordinate,
                    photoFilename: filename,
                    confidence: pending.confidence,
                    wasCaptive: pending.wasCaptive
                )
                context.insert(record)
                try context.save()
            } catch {
                // The animation has already promised a catch; losing it silently
                // would be worse than a visible failure, so surface it.
                Haptics.failed()
            }
        }
    }
}
