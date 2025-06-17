import SwiftUI

struct FarcasterView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var newPostText = ""
    @State private var showingNewPost = false
    @FocusState private var isNewPostFocused: Bool
    
    var body: some View {
        HSplitView {
            // Native macOS sidebar
            refinedChannelSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            
            // Main content area
            VStack(spacing: 0) {
                // Native toolbar-style header
                cleanFeedHeader
                
                // Content feed
                cleanPostsFeed
            }
            .background(
                ZStack {
                    DesignSystem.Colors.background(for: appState.currentTheme)
                    Rectangle()
                        .fill(.regularMaterial)
                }
            )
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
    
    // MARK: - Native macOS Sidebar
    private var refinedChannelSidebar: some View {
        VStack(spacing: 0) {
            // Native sidebar header
            HStack {
                Label("Channels", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Button(action: { core.handleEvent(.farcasterRefreshFeed) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh channels")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Native list style
            List {
                ForEach(appState.farcasterState.channels, id: \.id) { channel in
                    refinedChannelRow(channel)
                }
            }
            .listStyle(SidebarListStyle())
            .scrollContentBackground(.hidden)
            .background(Rectangle().fill(.ultraThinMaterial))
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme).opacity(0.95))
    }
    
    private func refinedChannelRow(_ channel: FarcasterChannel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.farcasterState.selectedChannel == channel.id ? 
                    DesignSystem.Colors.primary : 
                    DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    .lineLimit(1)
                
                Text("\(channel.memberCount) members")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            }
            
            Spacer()
            
            if appState.farcasterState.selectedChannel == channel.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityIdentifier("\(AccessibilityIdentifiers.farcasterChannelPrefix)\(channel.id)")
        .onTapGesture {
            core.handleEvent(.farcasterSelectChannel(channel.id))
        }
    }
    
    // MARK: - Native macOS Toolbar Header
    private var cleanFeedHeader: some View {
        HStack(spacing: 16) {
            if let selectedChannel = appState.farcasterState.channels.first(where: { $0.id == appState.farcasterState.selectedChannel }) {
                HStack(spacing: 8) {
                    Image(systemName: "number.circle")
                        .font(.system(size: 16, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedChannel.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        
                        Text("\(selectedChannel.memberCount) members · \(filteredPosts.count) casts")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                }
            }
            
            Spacer()
            
            // Native macOS-style compose button
            Button(action: {
                showingNewPost.toggle()
                if showingNewPost {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewPostFocused = true
                    }
                }
            }) {
                Label("New Cast", systemImage: "square.and.pencil")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(PrimaryButtonStyle())
                .foregroundColor(.white)
                .cornerRadius(16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
    
    // MARK: - Native macOS Posts Feed
    private var cleanPostsFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Animated composer
                if showingNewPost {
                    compactNewPostComposer
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
                
                // Posts with native dividers
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    if post.id != filteredPosts.last?.id {
                        Divider()
                            .background(DesignSystem.Colors.border(for: appState.currentTheme))
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: showingNewPost)
    }
    
    private var filteredPosts: [FarcasterPost] {
        appState.farcasterState.posts.filter { post in
            post.channel == appState.farcasterState.selectedChannel
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Native macOS Post Composer
    private var compactNewPostComposer: some View {
        VStack(spacing: 0) {
            // Text editor area
            TextEditor(text: $newPostText)
                .focused($isNewPostFocused)
                .frame(minHeight: 80, maxHeight: 200)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(16)
                .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Bottom toolbar
            HStack {
                // Character count
                Text("\(newPostText.count)/320")
                    .font(.system(size: 11))
                    .foregroundColor(newPostText.count > 320 ? DesignSystem.Colors.error : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingNewPost = false
                            newPostText = ""
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    
                    Button("Cast") {
                        if !newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            core.handleEvent(.farcasterCreatePost(newPostText))
                            newPostText = ""
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingNewPost = false
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPostText.count > 320)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Materials.titleBar)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
            // Native macOS post header
            HStack(spacing: 10) {
                // User avatar with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: Double(post.author.username.hashValue % 360) / 360.0, saturation: 0.5, brightness: 0.8),
                                    Color(hue: Double(post.author.username.hashValue % 360) / 360.0, saturation: 0.7, brightness: 0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Text(String(post.author.displayName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    HStack(spacing: 4) {
                        Text("@\(post.author.username)")
                        Text("•")
                        Text(timeAgoString(from: post.timestamp))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                }
                
                Spacer()
                
                // More menu
                Menu {
                    Button("Copy Link", action: {})
                    Button("Share...", action: {})
                    Divider()
                    Button("Mute User", action: {})
                    Button("Report", role: .destructive, action: {})
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
            
            // Post content with better typography
            Text(post.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            // Native macOS interaction buttons
            HStack(spacing: 20) {
                // Reply
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingReply.toggle()
                        if showingReply {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isReplyFocused = true
                            }
                        }
                    }
                }) {
                    Label(post.replies > 0 ? "\(post.replies)" : "Reply", systemImage: "bubble.left")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(showingReply ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reply to cast")
                
                // Recast
                Button(action: {
                    withAnimation(DesignSystem.Animation.socialInteraction) {
                        onRecast()
                    }
                }) {
                    Label(post.recasts > 0 ? "\(post.recasts)" : "Recast", systemImage: "arrow.2.squarepath")
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(post.isRecast ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Recast")
                .scaleEffect(post.isRecast ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.socialInteraction, value: post.isRecast)
                
                // Like
                Button(action: {
                    withAnimation(DesignSystem.Animation.heartBeat) {
                        onLike()
                    }
                }) {
                    Label(post.likes > 0 ? "\(post.likes)" : "Like", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(post.isLiked ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Like")
                .scaleEffect(post.isLiked ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.heartBeat, value: post.isLiked)
                
                Spacer()
                
                // Share
                Menu {
                    Button("Copy Link", action: {})
                    Button("Share to Twitter", action: {})
                    Button("Share to Mastodon", action: {})
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("Share")
            }
            
            // Native macOS reply composer
            if showingReply {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        // Reply indicator
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .padding(.leading, 4)
                        
                        // Reply text field
                        TextField("Write a reply...", text: $replyText, axis: .vertical)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12))
                            .lineLimit(1...4)
                            .focused($isReplyFocused)
                            .onSubmit {
                                if !replyText.isEmpty {
                                    onReply(replyText)
                                    replyText = ""
                                    showingReply = false
                                }
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.surface(for: theme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        isReplyFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme),
                                        lineWidth: isReplyFocused ? 1 : 0.5
                                    )
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isReplyFocused)
                    
                    // Send button
                    Button(action: {
                        if !replyText.isEmpty {
                            onReply(replyText)
                            replyText = ""
                            showingReply = false
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(replyText.isEmpty ? 
                                DesignSystem.Colors.textTertiary(for: theme) : 
                                DesignSystem.Colors.primary
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(replyText.isEmpty)
                    .help("Send reply")
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