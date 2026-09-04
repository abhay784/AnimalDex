import SwiftUI

/// Friends list, requests, and the add-by-handle field.
struct FriendsSection: View {
    @Environment(SessionStore.self) private var session
    @State private var newHandle = ""
    @State private var selected: FriendDTO?

    private var incoming: [FriendDTO] { session.friends.filter { $0.isPending && $0.incoming } }
    private var outgoing: [FriendDTO] { session.friends.filter { $0.isPending && !$0.incoming } }
    private var accepted: [FriendDTO] { session.friends.filter(\.isAccepted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FRIENDS")
                .font(Theme.display(12))
                .tracking(1.4)
                .foregroundStyle(Theme.outline.opacity(0.7))

            addField

            if !incoming.isEmpty {
                label("WANTS TO BE FRIENDS")
                ForEach(incoming) { friend in requestRow(friend) }
            }
            if !accepted.isEmpty {
                label("YOUR FRIENDS")
                ForEach(accepted) { friend in friendRow(friend) }
            }
            if !outgoing.isEmpty {
                label("REQUEST SENT")
                ForEach(outgoing) { friend in
                    HStack {
                        avatar(friend)
                        Text(friend.handle).font(Theme.display(12)).foregroundStyle(Theme.outline)
                        Spacer()
                        Text("PENDING")
                            .font(Theme.display(9))
                            .foregroundStyle(Theme.outline.opacity(0.5))
                    }
                }
            }
            if session.friends.isEmpty {
                Text("No friends yet. Add someone by their handle.")
                    .font(Theme.screenText(10))
                    .foregroundStyle(Theme.outline.opacity(0.6))
            }
        }
        .padding(14)
        .bevelPanel()
        .task { await session.loadFriends() }
        .sheet(item: $selected) { friend in
            FriendDexView(friend: friend)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.display(9))
            .tracking(1.2)
            .foregroundStyle(Theme.outline.opacity(0.5))
            .padding(.top, 4)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("handle", text: $newHandle)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(Theme.screenText(12))
                .foregroundStyle(Theme.phosphor)
                .padding(8)
                .screenSurface(Theme.lcd, radius: 7)

            Button {
                let handle = newHandle.trimmingCharacters(in: .whitespaces)
                guard !handle.isEmpty else { return }
                SoundBank.shared.play(.select)
                Task {
                    await session.addFriend(handle: handle)
                    newHandle = ""
                }
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Theme.panel)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lens))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .disabled(newHandle.isEmpty)
        }
    }

    private func avatar(_ friend: FriendDTO) -> some View {
        Circle()
            .fill(Theme.lens)
            .frame(width: 30, height: 30)
            .overlay(
                Text(String(friend.handle.prefix(1)).uppercased())
                    .font(Theme.display(13))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
    }

    private func requestRow(_ friend: FriendDTO) -> some View {
        HStack(spacing: 10) {
            avatar(friend)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.displayName).font(Theme.display(12)).foregroundStyle(Theme.outline)
                Text("@\(friend.handle)").font(Theme.screenText(9)).foregroundStyle(Theme.outline.opacity(0.6))
            }
            Spacer()
            Button {
                Task { await session.accept(friend) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Circle().fill(Theme.ledGreen))
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
            }
            .buttonStyle(.plain)
            Button {
                Task { await session.decline(friend) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Circle().fill(Theme.ledRed))
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }

    private func friendRow(_ friend: FriendDTO) -> some View {
        Button {
            SoundBank.shared.play(.select)
            selected = friend
        } label: {
            HStack(spacing: 10) {
                avatar(friend)
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.displayName).font(Theme.display(12)).foregroundStyle(Theme.outline)
                    Text("@\(friend.handle)").font(Theme.screenText(9)).foregroundStyle(Theme.outline.opacity(0.6))
                }
                Spacer()
                Text("\(friend.speciesCount)")
                    .font(Theme.display(14))
                    .foregroundStyle(Theme.outline)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.outline.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }
}

/// A friend's dex, fetched on demand. Their uncaught species stay hidden exactly
/// as yours do — the server only ever returns what they have actually caught.
struct FriendDexView: View {
    let friend: FriendDTO

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [DexEntryDTO] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .font(Theme.screenText(11))
                        .foregroundStyle(Theme.phosphor)
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(entries, id: \.speciesKey) { entry in
                                if let species = catalog.species(forLabel: entry.speciesKey) {
                                    tile(species, count: entry.count)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .background(Theme.phosphorDim)
            .navigationTitle("@\(friend.handle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            do {
                entries = try await session.client.friendDex(id: friend.id)
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func tile(_ species: Species, count: Int) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.phosphor
                Image(systemName: species.taxonType.systemImage)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Theme.outline.opacity(0.55))
                if count > 1 {
                    Text("×\(count)")
                        .font(Theme.display(10))
                        .outlinedText()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.outline.opacity(0.8)))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: 70)
            .overlay(Scanlines().opacity(0.09))

            Text(species.commonName.uppercased())
                .font(Theme.display(9))
                .foregroundStyle(Theme.outline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(species.rarity.color.opacity(0.35))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(species.rarity.color, lineWidth: 3))
    }
}
