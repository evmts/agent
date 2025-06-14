import SwiftUI

struct FarcasterView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var newPostText = ""
    @State private var showingNewPost = false
    @FocusState private var isNewPostFocused: Bool
    
    var body: some View {
        HSplitView {
            // Left sidebar - Channels
            channelSidebar
                .frame(minWidth: 250, maxWidth: 300)
            
            // Main content - Posts feed
            VStack(spacing: 0) {
                // Header with channel info and new post button
                feedHeader
                
                Divider()
                    .background(DesignSystem.Colors.border)
                
                // Posts feed
                postsFeed
            }
        }
        // Use the main content background from the design system
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    // MARK: - Channel Sidebar
    private var channelSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Text("Channels")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    core.handleEvent(.farcasterRefreshFeed)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh feed")
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
                .background(DesignSystem.Colors.border)
            
            // Channels list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.farcasterState.channels, id: \.id) { channel in
                        channelRow(channel)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
        }
    }
    
    private func channelRow(_ channel: FarcasterChannel) -> some View {
        Button(action: {
            core.handleEvent(.farcasterSelectChannel(channel.id))
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(channel.name)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(appState.farcasterState.selectedChannel == channel.id ? .white : .primary)
                    
                    Text(channel.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Text("\(channel.memberCount) members")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                if appState.farcasterState.selectedChannel == channel.id {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(appState.farcasterState.selectedChannel == channel.id ? 
                          Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    // MARK: - Feed Header
    private var feedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let selectedChannel = appState.farcasterState.channels.first(where: { $0.id == appState.farcasterState.selectedChannel }) {
                    Text("#\(selectedChannel.name)")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text(selectedChannel.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
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
                    Text("New Cast")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(DesignSystem.Colors.surface)
    }
    
    // MARK: - Posts Feed
    private var postsFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // New post composer (if showing)
                if showingNewPost {
                    newPostComposer
                }
                
                // Posts list
                ForEach(filteredPosts) { post in
                    PostView(
                        post: post,
                        onLike: { core.handleEvent(.farcasterLikePost(post.id)) },
                        onRecast: { core.handleEvent(.farcasterRecastPost(post.id)) },
                        onReply: { replyText in 
                            core.handleEvent(.farcasterReplyToPost(post.id, replyText))
                        }
                    )
                    
                    Divider()
                        .background(DesignSystem.Colors.border)
                }
            }
        }
        .background(DesignSystem.Colors.background)
    }
    
    private var filteredPosts: [FarcasterPost] {
        appState.farcasterState.posts.filter { post in
            post.channel == appState.farcasterState.selectedChannel
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - New Post Composer
    private var newPostComposer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Text("New Cast")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        showingNewPost = false
                        newPostText = ""
                    }
                    .foregroundColor(.secondary)
                    
                    Button("Cast") {
                        if !newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            core.handleEvent(.farcasterCreatePost(newPostText))
                            newPostText = ""
                            showingNewPost = false
                        }
                    }
                    .disabled(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                
                TextEditor(text: $newPostText)
                    .focused($isNewPostFocused)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
                .background(DesignSystem.Colors.border)
        }
    }
}

// MARK: - Post View
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