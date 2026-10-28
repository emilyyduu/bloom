import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// The Profile tab: who I am, plus the rows that used to be scattered
// across separate tabs (My Circle, Monthly Journals) or missing entirely
// (Edit Profile, Settings).
struct ProfileView: View {
    @State private var username: String = ""
    @State private var isLoadingUsername = true
    @ScaledMetric(relativeTo: .largeTitle) private var avatarIconSize: CGFloat = 44
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader("Profile")

                List {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: avatarIconSize))
                                .foregroundStyle(.secondary)
                            if isLoadingUsername {
                                Text("Loading...")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(username.isEmpty ? "Bloom User" : username)
                                    .font(.headline)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        NavigationLink {
                            EditProfileView(username: username) { updated in
                                username = updated
                            }
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        NavigationLink {
                            MyCircleView()
                        } label: {
                            Label("My Circle", systemImage: "person.2")
                        }
                        NavigationLink {
                            MonthlyJournalsListView()
                        } label: {
                            Label("Monthly Journals", systemImage: "book.closed")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
                .listSectionSpacing(isCompactHeight ? .compact : .default)
                .frame(maxWidth: isCompactHeight ? 700 : .infinity)
                .frame(maxWidth: .infinity)
            }
            // Matches the List's own grouped background, so the clear
            // area behind the header isn't a different colour than the
            // list beneath it.
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadUsername()
            }
        }
    }

    private func loadUsername() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoadingUsername = false
            return
        }

        let docRef = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await docRef.getDocument()
            let data = snapshot.data()
            username = data?["username"] as? String ?? ""

            if !username.isEmpty, data?["usernameLower"] == nil {
                await backfillUsernameLower(docRef: docRef, username: username)
            }
        } catch {
            username = ""
        }
        isLoadingUsername = false
    }

    // Older profiles were created before usernameLower existed, and
    // some may still carry a leftover "email" field from before the
    // Firestore rules started rejecting any extra field on this
    // document. Both are fixed here, the moment the signed-in user's
    // own profile is loaded. Failures are ignored quietly since this is
    // a best-effort migration, not something the user can act on.
    private func backfillUsernameLower(docRef: DocumentReference, username: String) async {
        do {
            try await docRef.updateData([
                "usernameLower": username.lowercased(),
                "email": FieldValue.delete(),
            ])
        } catch {
            #if DEBUG
            print("ProfileView: failed to backfill usernameLower for existing profile: \(error)")
            #endif
        }
    }
}

#Preview("Light") {
    ProfileView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ProfileView()
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    ProfileView()
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    ProfileView()
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    ProfileView()
        .environment(\.dynamicTypeSize, .accessibility5)
}
