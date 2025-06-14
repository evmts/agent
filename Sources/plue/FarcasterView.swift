import SwiftUI

struct FarcasterView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var newPostText = ""
    @State private var showingNewPost = false
    @FocusState private var isNewPostFocused: Bool
    
    var body: some View {
        HSplitView {
            // Clean sidebar with refined channels
            refinedChannelSidebar
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 280)
            
            // Main content with cleaner feed
            VStack(spacing: 0) {
                // Cleaner header without heavy chrome
                cleanFeedHeader
                
                // Refined posts feed with better spacing
                cleanPostsFeed
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
    
    // MARK: - Refined Channel Sidebar
    private var refinedChannelSidebar: some View {
        VStack(spacing: 0) {
            // Minimal sidebar header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Social")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("farcaster channels")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                Button(action: { core.handleEvent(.farcasterRefreshFeed) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh feed")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
            
            // Clean channels list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(appState.farcasterState.channels, id: \.id) { channel in
                        refinedChannelRow(channel)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
    }
    
    private func refinedChannelRow(_ channel: FarcasterChannel) -> some View {
        Button(action: {
            core.handleEvent(.farcasterSelectChannel(channel.id))
        }) {
            HStack(spacing: 12) {
                // Channel indicator
                Circle()
                    .fill(appState.farcasterState.selectedChannel == channel.id ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.3))
                    .frame(width: 6, height: 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(
                            appState.farcasterState.selectedChannel == channel.id 
                                ? DesignSystem.Colors.textPrimary(for: appState.currentTheme)
                                : DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                        )
                        .lineLimit(1)
                    
                    Text("\(channel.memberCount)")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.farcasterState.selectedChannel == channel.id ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            )
            .animation(DesignSystem.Animation.plueStandard, value: appState.farcasterState.selectedChannel == channel.id)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
    
    // MARK: - Clean Feed Header
    private var cleanFeedHeader: some View {
        HStack(spacing: 16) {
            if let selectedChannel = appState.farcasterState.channels.first(where: { $0.id == appState.farcasterState.selectedChannel }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedChannel.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(selectedChannel.memberCount) members")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
            }
            
            Spacer()
            
            // Compact new cast button
            Button(action: {
                showingNewPost.toggle()
                if showingNewPost {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewPostFocused = true
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Cast")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesignSystem.Colors.primary)
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
    
    // MARK: - Clean Posts Feed
    private var cleanPostsFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Compact new post composer
                if showingNewPost {
                    compactNewPostComposer
                }
                
                // Clean posts list with better spacing
                ForEach(filteredPosts) { post in
                    CompactPostView(
                        post: post,
                        theme: appState.currentTheme,
                        onLike: { core.handleEvent(.farcasterLikePost(post.id)) },
                        onRecast: { core.handleEvent(.farcasterRecastPost(post.id)) },
                        onReply: { replyText in 
                            core.handleEvent(.farcasterReplyToPost(post.id, replyText))
                        }
                    )
                    
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.2))
                }
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
    
    private var filteredPosts: [FarcasterPost] {
        appState.farcasterState.posts.filter { post in
            post.channel == appState.farcasterState.selectedChannel
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Compact New Post Composer
    private var compactNewPostComposer: some View {
        VStack(spacing: 12) {
            HStack {
                Text("New Cast")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Button("Cancel") {
                    showingNewPost = false
                    newPostText = ""
                }
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                .buttonStyle(PlainButtonStyle())
                
                Button("Cast") {
                    if !newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        core.handleEvent(.farcasterCreatePost(newPostText))
                        newPostText = ""
                        showingNewPost = false
                    }
                }
                .disabled(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.2) : DesignSystem.Colors.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
                .buttonStyle(PlainButtonStyle())
            }
            
            TextEditor(text: $newPostText)
                .focused($isNewPostFocused)
                .frame(minHeight: 60)
                .font(.system(size: 13))
                .padding(10)
                .background(DesignSystem.Colors.surface(for: appState.currentTheme))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
                )
        }
        .padding(16)
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
}

// MARK: - Compact Post View
struct CompactPostView: View {
    let post: FarcasterPost
    let theme: DesignSystem.Theme
    let onLike: () -> Void
    let onRecast: () -> Void
    let onReply: (String) -> Void
    
    @State private var showingReply = false
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Compact post header
            HStack(spacing: 10) {
                // Smaller, cleaner avatar
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(post.author.displayName.prefix(1)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(post.author.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        
                        Text("@\(post.author.username)")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        
                        Text(timeAgoString(from: post.timestamp))
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                    }
                }
                
                Spacer()
            }
            
            // Post content with better typography
            Text(post.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            // Compact interaction buttons
            HStack(spacing: 24) {
                // Reply
                Button(action: {
                    showingReply.toggle()
                    if showingReply {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isReplyFocused = true
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("\(post.replies)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Recast with bounce animation
                Button(action: {
                    withAnimation(DesignSystem.Animation.socialInteraction) {
                        onRecast()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(post.isRecast ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary(for: theme))
                            .rotationEffect(.degrees(post.isRecast ? 360 : 0))
                            .animation(DesignSystem.Animation.socialInteraction, value: post.isRecast)
                        Text("\(post.recasts)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(post.isRecast ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary(for: theme))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(post.isRecast ? 1.1 : 1.0)
                .animation(DesignSystem.Animation.socialInteraction, value: post.isRecast)
                
                // Like with heart animation
                Button(action: {
                    withAnimation(DesignSystem.Animation.heartBeat) {
                        onLike()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(post.isLiked ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary(for: theme))
                            .scaleEffect(post.isLiked ? 1.2 : 1.0)
                            .animation(DesignSystem.Animation.heartBeat, value: post.isLiked)
                        Text("\(post.likes)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(post.isLiked ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary(for: theme))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(post.isLiked ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.socialInteraction, value: post.isLiked)
                
                Spacer()
            }
            
            // Compact reply composer with slide animation
            if showingReply {
                VStack(spacing: 8) {
                    HStack {
                        TextEditor(text: $replyText)
                            .focused($isReplyFocused)
                            .frame(minHeight: 50)
                            .font(.system(size: 13))
                            .padding(8)
                            .background(DesignSystem.Colors.surface(for: theme))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: 1)
                            )
                        
                        VStack(spacing: 6) {
                            Button("Reply") {
                                if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    withAnimation(DesignSystem.Animation.socialInteraction) {
                                        onReply(replyText)
                                        replyText = ""
                                        showingReply = false
                                    }
                                }
                            }
                            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                      DesignSystem.Colors.textTertiary(for: theme).opacity(0.2) : DesignSystem.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .buttonStyle(PlainButtonStyle())
                            .scaleEffect(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.95 : 1.0)
                            .animation(DesignSystem.Animation.buttonPress, value: replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button("Cancel") {
                                withAnimation(DesignSystem.Animation.slideTransition) {
                                    showingReply = false
                                    replyText = ""
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(DesignSystem.Animation.slideTransition, value: showingReply)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Legacy Post View (keeping for reference)
struct PostView: View {
    let post: FarcasterPost
    let onLike: () -> Void
    let onRecast: () -> Void
    let onReply: (String) -> Void
    
    @State private var showingReply = false
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header with user info
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(post.author.displayName.prefix(1)))
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(post.author.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("@\(post.author.username)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(timeAgoString(from: post.timestamp))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("#\(post.channel)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue.opacity(0.8))
                }
                
                Spacer()
            }
            
            // Post content
            Text(post.content)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(nil)
            
            // Interaction buttons
            HStack(spacing: 32) {
                // Reply
                Button(action: {
                    showingReply.toggle()
                    if showingReply {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isReplyFocused = true
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                        Text("\(post.replies)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Recast
                Button(action: onRecast) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 16))
                        Text("\(post.recasts)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(post.isRecast ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Like
                Button(action: onLike) {
                    HStack(spacing: 6) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                        Text("\(post.likes)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(post.isLiked ? .red : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            // Reply composer
            if showingReply {
                VStack(spacing: 8) {
                    HStack {
                        Text("Reply to @\(post.author.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            showingReply = false
                            replyText = ""
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        TextEditor(text: $replyText)
                            .focused($isReplyFocused)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(8)
                        
                        Button("Reply") {
                            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onReply(replyText)
                                replyText = ""
                                showingReply = false
                            }
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                  Color.secondary.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                .cornerRadius(8)
            }
        }
        .padding()
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

#Preview {
    FarcasterView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}