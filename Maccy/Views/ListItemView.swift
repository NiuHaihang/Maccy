import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  var appIcon: ApplicationImage? = nil
  var image: NSImage? = nil
  var accessoryImage: NSImage? = nil
  var attributedTitle: AttributedString? = nil
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var timeLabel: String? = nil
  var typeLabel: String? = nil
  var appName: String? = nil
  var statsLabel: String? = nil
  var help: LocalizedStringKey? = nil
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    if Defaults[.popupPosition] == .bottom {
      let headerColor: Color = if typeLabel == "Image" {
        Color(red: 0.98, green: 0.84, blue: 0.53) // Photo/Yellow
      } else if typeLabel == "File" {
         Color(red: 0.75, green: 0.85, blue: 0.98) // File/Blue
      } else if typeLabel == "HTML" || typeLabel == "RTF" {
         Color(red: 0.44, green: 0.86, blue: 0.58) // Rich Text/Green
      } else {
        Color(red: 0.44, green: 0.86, blue: 0.58) // Text/Green
      }

      VStack(spacing: 0) {
        // --- Card Header ---
        ZStack {
          Rectangle()
            .fill(headerColor)
          
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
              Text(typeLabel ?? "Text")
                .font(.system(size: 11, weight: .bold))
              Text(timeLabel ?? "")
                .font(.system(size: 9))
                .opacity(0.6)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
              HStack(spacing: 4) {
                Text(appName ?? "Unknown")
                  .font(.system(size: 9))
                  .opacity(0.8)
                if showIcons, let appIcon {
                  Image(nsImage: appIcon.nsImage)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(.rect(cornerRadius: 3))
                }
              }
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .foregroundStyle(.black.opacity(0.8))
        }
        .frame(height: 40)

        // --- Card Content ---
        VStack(spacing: 0) {
          if let image {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .padding(10)
          } else {
            ScrollView {
              ListItemTitleView(attributedTitle: attributedTitle, title: title)
                .font(.system(size: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .scrollDisabled(true)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))

        // --- Card Footer ---
        HStack {
          // Index (shortcuts)
          if !shortcuts.isEmpty {
             Text(shortcuts.first?.character ?? "")
               .font(.system(size: 10, weight: .bold))
               .foregroundStyle(Color.cyan)
          }
          
          Spacer()
          
          // Stats
          Text(statsLabel ?? "")
               .font(.system(size: 9))
               .foregroundStyle(.secondary)
          
          Spacer()
          
          // Actions
          HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.left")
              .font(.system(size: 10))
              .foregroundStyle(.cyan)
            Image(systemName: "doc.on.doc")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
      }
      .frame(width: Popup.cardSize, height: Popup.cardSize)
      .background(Color(NSColor.windowBackgroundColor))
      .clipShape(.rect(cornerRadius: 16))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(isSelected ? headerColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
      )
      .onHover { hovering in
        if hovering {
          if !appState.isKeyboardNavigating {
            appState.selectWithoutScrolling(id)
          } else {
            appState.hoverSelectionWhileKeyboardNavigating = id
          }
        }
      }
    } else {
      HStack(spacing: 0) {
        if showIcons, let appIcon {
          VStack {
            Spacer(minLength: 0)
            Image(nsImage: appIcon.nsImage)
              .resizable()
              .frame(width: 15, height: 15)
            Spacer(minLength: 0)
          }
          .padding(.leading, 4)
          .padding(.vertical, 5)
        }

        Spacer()
          .frame(width: showIcons ? 5 : 10)

        if let accessoryImage {
          Image(nsImage: accessoryImage)
            .accessibilityIdentifier("copy-history-item")
            .padding(.trailing, 5)
            .padding(.vertical, 5)
        }

        if let image {
          Image(nsImage: image)
            .accessibilityIdentifier("copy-history-item")
            .padding(.trailing, 5)
            .padding(.vertical, 5)
        } else {
          ListItemTitleView(attributedTitle: attributedTitle, title: title)
            .padding(.trailing, 5)
        }

        Spacer()

        if !shortcuts.isEmpty {
          ZStack {
            ForEach(shortcuts) { shortcut in
              KeyboardShortcutView(shortcut: shortcut)
                .opacity(shortcut.isVisible(shortcuts, modifierFlags.flags) ? 1 : 0)
            }
          }
          .padding(.trailing, 10)
        } else {
          Spacer()
            .frame(width: 50)
        }
      }
      .frame(height: Popup.cardSize)
      .id(id)
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(isSelected ? Color.white : .primary)
      // macOS 26 broke hovering if no background is present.
      // The slight opcaity white background is a workaround
      .background(isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001))
      .clipShape(.rect(cornerRadius: Popup.cornerRadius))
      .onHover { hovering in
        if hovering {
          if !appState.isKeyboardNavigating {
            appState.selectWithoutScrolling(id)
          } else {
            appState.hoverSelectionWhileKeyboardNavigating = id
          }
        }
      }
      .help(help ?? "")
    }
  }
}
