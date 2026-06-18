import SwiftUI

@MainActor
class GitHubRepoModel: ObservableObject {
    @Published var starCount: Int = 1000
    @Published var ownerAvatarUrl: String = "https://avatars.githubusercontent.com/u/227873155?v=4"
    @Published var stargazers: [String] = [
        "https://avatars.githubusercontent.com/u/1?v=4",
        "https://avatars.githubusercontent.com/u/2?v=4",
        "https://avatars.githubusercontent.com/u/3?v=4",
        "https://avatars.githubusercontent.com/u/4?v=4",
        "https://avatars.githubusercontent.com/u/5?v=4",
        "https://avatars.githubusercontent.com/u/6?v=4",
        "https://avatars.githubusercontent.com/u/7?v=4",
        "https://avatars.githubusercontent.com/u/8?v=4",
        "https://avatars.githubusercontent.com/u/17?v=4",
        "https://avatars.githubusercontent.com/u/18?v=4",
        "https://avatars.githubusercontent.com/u/19?v=4",
        "https://avatars.githubusercontent.com/u/20?v=4",
        "https://avatars.githubusercontent.com/u/21?v=4"
    ]
    
    private var hasFetched = false
    
    func fetchData() async {
        guard !hasFetched else { return }
        hasFetched = true
        
        guard let repoURL = URL(string: "https://api.github.com/repos/AdityaManshukhani-Coding/Open-Cowork") else { return }
        var repoRequest = URLRequest(url: repoURL)
        repoRequest.setValue("Open-Cowork-App", forHTTPHeaderField: "User-Agent")
        
        do {
            let (repoData, _) = try await URLSession.shared.data(for: repoRequest)
            if let json = try JSONSerialization.jsonObject(with: repoData) as? [String: Any] {
                if let stars = json["stargazers_count"] as? Int, stars > 0 {
                    self.starCount = max(stars, 1000)
                }
                if let owner = json["owner"] as? [String: Any], let avatar = owner["avatar_url"] as? String {
                    self.ownerAvatarUrl = avatar
                }
            }
        } catch {
            print("Failed to fetch GitHub repo: \(error)")
        }
        
        guard let stargazersURL = URL(string: "https://api.github.com/repos/AdityaManshukhani-Coding/Open-Cowork/stargazers?per_page=20") else { return }
        var stargazersRequest = URLRequest(url: stargazersURL)
        stargazersRequest.setValue("Open-Cowork-App", forHTTPHeaderField: "User-Agent")
        
        do {
            let (stargazersData, _) = try await URLSession.shared.data(for: stargazersRequest)
            if let jsonArray = try JSONSerialization.jsonObject(with: stargazersData) as? [[String: Any]] {
                let avatars = jsonArray.compactMap { $0["avatar_url"] as? String }
                if !avatars.isEmpty {
                    var combined = avatars
                    let fallbacks = [
                        "https://avatars.githubusercontent.com/u/1?v=4",
                        "https://avatars.githubusercontent.com/u/2?v=4",
                        "https://avatars.githubusercontent.com/u/3?v=4",
                        "https://avatars.githubusercontent.com/u/4?v=4",
                        "https://avatars.githubusercontent.com/u/5?v=4",
                        "https://avatars.githubusercontent.com/u/6?v=4",
                        "https://avatars.githubusercontent.com/u/7?v=4",
                        "https://avatars.githubusercontent.com/u/8?v=4",
                        "https://avatars.githubusercontent.com/u/17?v=4",
                        "https://avatars.githubusercontent.com/u/18?v=4",
                        "https://avatars.githubusercontent.com/u/19?v=4",
                        "https://avatars.githubusercontent.com/u/20?v=4",
                        "https://avatars.githubusercontent.com/u/21?v=4"
                    ]
                    for fallback in fallbacks {
                        if combined.count < 14 && !combined.contains(fallback) {
                            combined.append(fallback)
                        }
                    }
                    self.stargazers = combined
                }
            }
        } catch {
            print("Failed to fetch GitHub stargazers: \(error)")
        }
    }
}

struct WelcomeView: View {
    var onContinue: () -> Void
    @StateObject private var gitHubModel = GitHubRepoModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundColor(.primary)
            
            // Welcome header
            VStack(spacing: 8) {
                Text("Welcome to Open Cowork")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("Your AI desktop agent — free, open-source, and fully transparent.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
                       // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "computermouse.fill", text: "Real mouse & keyboard control on your Mac")
                featureRow(icon: "key.fill", text: "Bring your own API key — zero markup")
                featureRow(icon: "eye.fill", text: "Live action log — see every click and keystroke")
                featureRow(icon: "shield.checkered", text: "Safety-first with approve-before-action mode")
            }
            .padding(16)
            .background(Color(white: 0.97))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 24)
            
            Spacer()
            
            // GitHub Card
            GitHubCardView(model: gitHubModel)
                .padding(.horizontal, 24)
            
            // Continue button
            Button(action: onContinue) {
                HStack {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Color.black)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .contentShape(Rectangle())
            .padding(.horizontal, 24)
            
            Spacer().frame(height: 16)
        }
        .padding(20)
        .task {
            await gitHubModel.fetchData()
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 22)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}
 
struct GitHubCardView: View {
    @ObservedObject var model: GitHubRepoModel
    @State private var isHovered = false
    
    private func formatStars(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Top Row
            HStack(spacing: 8) {
                // Owner Avatar
                AsyncImage(url: URL(string: model.ownerAvatarUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                
                // Repo Name
                Link(destination: URL(string: "https://github.com/AdityaManshukhani-Coding/Open-Cowork")!) {
                    Text("AdityaManshukhani-Coding/Open-Cowork")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Stars Badge
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.1))
                    Text("\(formatStars(model.starCount)) stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(red: 0.95, green: 0.75, blue: 0.1).opacity(0.15))
                .cornerRadius(12)
                
                // Star Action Button
                Link(destination: URL(string: "https://github.com/AdityaManshukhani-Coding/Open-Cowork")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Text("Star")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .background(Color.black.opacity(0.06))
                .padding(.vertical, 2)
            
            // Bottom Row
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(model.stargazers.prefix(12), id: \.self) { avatarUrl in
                        AsyncImage(url: URL(string: avatarUrl)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
                
                Text("recently starred")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.black.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
