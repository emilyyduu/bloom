import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// The Profile tab: who I am, plus the rows that used to be scattered
// across separate tabs (My Circle, Your Journals) or missing entirely
// (Edit Profile, Settings).
struct ProfileView: View {
    @State private var username: String = ""
    @State private var isLoadingUsername = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
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
                        JournalHistoryListView()
                    } label: {
                        Label("Your Journals", systemImage: "book.closed")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationTitle("Profile")
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
        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            username = snapshot.data()?["username"] as? String ?? ""
        } catch {
            username = ""
        }
        isLoadingUsername = false
    }
}

#Preview {
    ProfileView()
}
