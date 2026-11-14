import AppKit
import SwiftUI

/// Copies plain text to the macOS general pasteboard.
@MainActor
func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

/// Tri-state checkbox used for select-all table headers and individual rows.
enum TableCheckState {
    case unchecked, indeterminate, checked
}

/// Rounded 15×15 checkbox matching Penpot `01e` and `05–07`.
struct TableCheckbox: View {
    let state: TableCheckState
    var help: LocalizedStringKey? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: 1.2)
                .background(RoundedRectangle(cornerRadius: 4).fill(fillColor))
                .overlay {
                    switch state {
                    case .checked:
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.ctp.bg)
                    case .indeterminate:
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.ctp.accent)
                    case .unchecked:
                        EmptyView()
                    }
                }
                .frame(width: 15, height: 15)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help.map { Text($0, bundle: .l10n) } ?? Text(verbatim: ""))
    }

    private var fillColor: Color {
        switch state {
        case .checked: Color.ctp.accent
        case .indeterminate: Color.ctp.accent.opacity(0.18)
        case .unchecked: Color.clear
        }
    }

    private var borderColor: Color {
        switch state {
        case .checked, .indeterminate: Color.ctp.accent
        case .unchecked: Color.ctp.muted.opacity(0.55)
        }
    }
}

/// Unified table search input with `⌘K` keyboard focus shortcut and clear button.
struct TableSearchField: View {
    @Binding var text: String
    let prompt: String
    var width: CGFloat = 260
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)

            TextField(text: $text, prompt: Text(verbatim: prompt)) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isFocused)
            .frame(maxWidth: .infinity)

            if text.isEmpty {
                Text(verbatim: "⌘K")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ctp.muted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.ctp.hover.opacity(0.5))
                    )
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.ctp.side)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isFocused ? Color.ctp.accent : Color.ctp.muted.opacity(0.28),
                            lineWidth: 1
                        )
                )
        )
        .background {
            Button("") { isFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }
}

/// Draggable vertical column divider clamped to `minWidth`, changing cursor to `resizeLeftRight` on hover.
struct ColumnResizeDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    var maxWidth: CGFloat = 900

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(isHovering || dragStartWidth != nil ? Color.ctp.accent : Color.ctp.muted.opacity(0.35))
            .frame(width: 2, height: 14)
            .frame(width: 10, height: 22)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering && !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !hovering && cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? width
                        if dragStartWidth == nil {
                            dragStartWidth = start
                        }
                        width = min(maxWidth, max(minWidth, start + value.translation.width))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

/// 28×28 rounded icon box used as leading visual anchor in resource rows (`Images`, `Volumes`, `Networks`, `Compose`).
struct ResourceRowIcon: View {
    let systemImage: String
    var tint: Color = Color.ctp.accent

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(tint.opacity(0.14))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}

/// 28×28 bordered `⋯` dropdown menu button matching `IconActionButton`.
struct SectionMenuButton<MenuContent: View>: View {
    var help: LocalizedStringKey? = nil
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var hovered = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ctp.text)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovered ? Color.ctp.text.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.ctp.text.opacity(hovered ? 0.55 : 0.28), lineWidth: 1)
                )
        )
        .onHover { hovered = $0 }
        .help(help.map { Text($0, bundle: .l10n) } ?? Text(verbatim: ""))
    }
}

/// Floating contextual action bar shown when one or more rows are checked.
struct BulkActionBar<Actions: View>: View {
    let selectedCount: Int
    let onClear: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: String(localized: "\(String(selectedCount)) selected", bundle: .l10n))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ctp.text)

            Divider()
                .frame(height: 16)
                .overlay(Color.ctp.muted.opacity(0.25))

            HStack(spacing: 8) {
                actions()
            }

            Divider()
                .frame(height: 16)
                .overlay(Color.ctp.muted.opacity(0.25))

            Button(action: onClear) {
                Text("Clear", bundle: .l10n)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ctp.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.side)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.ctp.muted.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        )
        .padding(.bottom, 12)
    }
}

/// Compact pill action button rendered inside `BulkActionBar`.
struct BulkPillButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = Color.ctp.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title, bundle: .l10n)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Shared disconnected / empty / search-empty placeholder for resource views.
struct ResourceEmptyState: View {
    let connected: Bool
    let isAllEmpty: Bool
    let searchText: String
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String

    var body: some View {
        if !connected {
            ContentUnavailableView {
                Label {
                    Text("Docker disconnected", bundle: .l10n)
                } icon: {
                    Image(systemName: "bolt.slash")
                }
            } description: {
                Text("Docker is not reachable. Ensure Docker Desktop or Docker Engine is running.", bundle: .l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isAllEmpty {
            ContentUnavailableView {
                Label {
                    Text(verbatim: emptyTitle)
                } icon: {
                    Image(systemName: emptySystemImage)
                }
            } description: {
                Text(verbatim: emptyDescription)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
