//
//  AccountManagerView.swift
//  MeloNX
//
//  Created by Stossy11 on 17/07/2025.
//

import SwiftUI

struct AccountManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: Profiles?
    @State private var showingCreation = false
    @State private var editingProfile: Account?
    @State private var removingProfile: Account?
    @State private var errorMessage: String?

    private let defaultUserID = "00000000000000010000000000000000"
    private let profilePath = URL.documentsDirectory
        .appendingPathComponent("system").appendingPathComponent("Profiles.json")

    var body: some View {
        NavigationStack {
            List {
                if let profiles {
                    ForEach(profiles.profiles) { profile in
                        HStack(spacing: 12) {
                            Button {
                                select(profile)
                            } label: {
                                HStack(spacing: 12) {
                                    avatar(profile)
                                    VStack(alignment: .leading) {
                                        Text(profile.name).font(.headline)
                                        if profile.id == profiles.last_opened {
                                            Label("Current", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingProfile = profile
                            } label: {
                                Image(systemName: "pencil")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(profile.name)")
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            if profile.id != defaultUserID {
                                Button(role: .destructive) {
                                    removingProfile = profile
                                } label: {
                                    Label("Remove Profile", systemImage: "trash")
                                }
                            }
                        }
                    }
                } else {
                    Button("Reload Profiles", action: loadAccounts)
                }
            }
            .navigationTitle("Profile Manager")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreation = true } label: {
                        Label("Create Profile", systemImage: "plus")
                    }
                    .disabled(profiles == nil)
                }
            }
        }
        .onAppear(perform: loadAccounts)
        .sheet(isPresented: $showingCreation, onDismiss: loadAccounts) {
            CreateAccount()
        }
        .sheet(item: $editingProfile, onDismiss: loadAccounts) { profile in
            EditAccount(account: profile)
        }
        .alert("Profile Manager", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Remove profile?", isPresented: Binding(
            get: { removingProfile != nil },
            set: { if !$0 { removingProfile = nil } }
        ), titleVisibility: .visible, presenting: removingProfile) { profile in
            Button("Remove \(profile.name)", role: .destructive) {
                remove(profile)
            }
        } message: { _ in
            Text("The profile will be removed from this list. Its save files will stay on this device.")
        }
    }

    @ViewBuilder
    private func avatar(_ profile: Account) -> some View {
        if let data = Data(base64Encoded: profile.image ?? ""), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
        }
    }

    private func loadAccounts() {
        do {
            profiles = try JSONDecoder().decode(Profiles.self, from: Data(contentsOf: profilePath))
        } catch {
            profiles = nil
            errorMessage = "Could not read the profile list. \(error.localizedDescription)"
        }
    }

    private func select(_ profile: Account) {
        guard profile.id != profiles?.last_opened else { return }
        guard Ryujinx.openUser(userId: profile.id) else {
            errorMessage = "Could not select \(profile.name)."
            return
        }
        loadAccounts()
    }

    private func remove(_ profile: Account) {
        guard profile.id != defaultUserID else { return }
        do {
            // Read the latest file and preserve fields used only by the engine.
            let data = try Data(contentsOf: profilePath)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var entries = root["profiles"] as? [[String: Any]] else {
                errorMessage = "Could not read the profile list."
                return
            }
            entries.removeAll { ($0["user_id"] as? String) == profile.id }
            guard !entries.isEmpty else { return }
            if (root["last_opened"] as? String) == profile.id {
                root["last_opened"] = entries.first(where: { ($0["user_id"] as? String) == defaultUserID })?["user_id"]
                    ?? entries.first?["user_id"]
            }
            root["profiles"] = entries
            try JSONSerialization.data(withJSONObject: root).write(to: profilePath, options: .atomic)
            Ryujinx.refreshAccountManager()
            loadAccounts()
        } catch {
            errorMessage = "Could not remove \(profile.name). \(error.localizedDescription)"
        }
    }
}
