import SwiftUI
import GitGazeCore

struct PeopleCard: View {
    @ObservedObject var store: Store
    let favouritesOnly: Bool
    private var people: [Person] { store.orderedPeople.filter { !favouritesOnly || store.favourites.contains($0.login) } }
    var body: some View {
        Card {
            sectionHeading(favouritesOnly ? "FAVOURITES" : "FOLLOWING")
            if let error = store.peopleError { Text(error).font(.system(size: 10)).foregroundStyle(Theme.gold) }
            if people.isEmpty { Text("Choose people in this widget’s settings.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 12) }
            ForEach(Array(people.prefix(store.peopleLimit))) { person in
                PersonRow(person: person, profile: store.dashboard?.people[person.login], today: store.today)
                if person.login != people.prefix(store.peopleLimit).last?.login { Divider().opacity(0.35).padding(.vertical, 7) }
            }
            if people.count > store.peopleLimit {
                Button("Show more") { store.peopleLimit += 12; Task { await store.loadPeople() } }.buttonStyle(QuietButtonStyle()).font(.system(size: 11))
            }
        }
    }
}

/// Search and ordering live only on the back face; the front never inherits the search state.
struct PeopleSettings: View {
    @ObservedObject var store: Store
    @State var search = ""
    @State private var limit = 20
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var matches: [Person] {
        store.orderedPeople.filter { search.isEmpty || $0.login.localizedCaseInsensitiveContains(search) || $0.displayName.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(searching ? Theme.accent : Color.secondary)
                TextField("Find someone you follow", text: $search).textFieldStyle(.plain).font(.system(size: 11)).focused($searching)
                if !search.isEmpty { IconButton(symbol: "xmark", label: "Clear search") { search = "" } }
            }.padding(.horizontal, 11).padding(.vertical, 9)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searching ? Theme.accent.opacity(0.65) : Color.primary.opacity(0.09)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: searching)
            ForEach(Array(matches.prefix(limit))) { person in
                let selected = store.favourites.contains(person.login)
                HStack(spacing: 9) {
                    PersonAvatar(person: person, size: 25)
                    Text(person.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1).help("@\(person.login)")
                    Spacer(minLength: 0)
                    if selected {
                        let favourites = store.orderedPeople.filter { store.favourites.contains($0.login) }
                        IconButton(symbol: "arrow.up", label: "Move \(person.login) up") { store.moveFavourite(person.login, by: -1) }
                            .disabled(favourites.first?.login == person.login)
                        IconButton(symbol: "arrow.down", label: "Move \(person.login) down") { store.moveFavourite(person.login, by: 1) }
                            .disabled(favourites.last?.login == person.login)
                    }
                    IconButton(symbol: selected ? "minus.circle" : "plus.circle", label: "\(selected ? "Unfavourite" : "Favourite") \(person.login)") { store.toggleFavourite(person.login) }
                }.padding(.vertical, 3)
            }
            if matches.isEmpty { Text("No matching people").font(.system(size: 11)).foregroundStyle(.secondary).padding(12) }
            if matches.count > limit { Button("Show more") { limit += 20 }.buttonStyle(QuietButtonStyle()) }
        }.animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.05), value: store.favouriteOrder)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.05), value: store.favourites)
    }
}

struct PersonAvatar: View {
    let person: Person
    var size: CGFloat = 27
    var body: some View {
        AsyncImage(url: URL(string: person.avatarUrl)) { image in image.resizable().scaledToFill() }
            placeholder: { Circle().fill(Theme.accent.opacity(0.2)).overlay(Text(String(person.login.prefix(1)).uppercased()).font(.system(size: 10, weight: .medium))) }
            .frame(width: size, height: size).clipShape(Circle())
    }
}

struct PersonRow: View {
    let person: Person
    let profile: Profile?
    let today: String
    @State var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        PersonAvatar(person: person, size: 21)
                        Link(destination: URL(string: "https://github.com/\(person.login)")!) {
                            Text(person.displayName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(QuietButtonStyle())
                    }
                    if let profile {
                        let stats = ContributionStats(days: profile.days, today: today)
                        HStack(spacing: 5) {
                            metric("Today", stats.todayCount)
                            metric("Week", stats.weekTotal)
                            metric("Month", stats.monthTotal)
                            metric("Year", stats.yearTotal)
                        }
                    } else { Text("History not loaded").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity)
                if let profile {
                    graph(profile, weeks: 26, dates: false).frame(width: 152, height: 47)
                }
            }
            if expanded, let profile {
                graph(profile, weeks: 53, dates: true).frame(height: 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }
    private func graph(_ profile: Profile, weeks: Int, dates: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.04)) { expanded.toggle() }
        } label: {
            Heatmap(days: profile.days, today: today, weeks: weeks, showDates: dates).padding(5)
                .background(Theme.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(TileButtonStyle()).help(expanded ? "Collapse full-year history" : "Expand full-year history")
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(person.login)’s contribution graph")
    }
    private func metric(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count.formatted()).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(title == "Today" && count > 0 ? Theme.accent : Color.primary)
            Text(title).font(.system(size: 7)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
