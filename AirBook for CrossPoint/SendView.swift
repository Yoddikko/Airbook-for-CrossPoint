import SwiftUI

// MARK: - Send View

struct SendView: View {
    let book: Book
    @Environment(BookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var bt = BluetoothManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.airBookBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    BookCoverView(book: book)
                        .frame(width: 150, height: 225)
                        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
                        .padding(.top, 36)

                    VStack(spacing: 4) {
                        Text(book.displayTitle)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)

                    Spacer()

                    TransferStatusArea(
                        state: bt.transferState,
                        progress: bt.progress,
                        transferred: bt.bytesTransferred,
                        total: bt.totalBytes
                    )
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.3), value: bt.transferState)

                    Spacer()

                    crossPointHint
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)

                    actionSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 44)
                }
            }
            .navigationTitle("Send Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .disabled(bt.transferState.isActive)
                        .foregroundStyle(bt.transferState.isActive ? Color.secondary : Color.airBookAccent)
                }
            }
            .interactiveDismissDisabled(bt.transferState.isActive)
            .onDisappear {
                if bt.transferState.isActive { bt.cancel() }
            }
        }
    }

    // MARK: Hint

    @ViewBuilder
    private var crossPointHint: some View {
        switch bt.transferState {
        case .idle, .scanning:
            Label {
                Text("On your CrossPoint: **Network → Bluetooth Receive**")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.secondary)
            }
            .multilineTextAlignment(.leading)
        default:
            EmptyView()
        }
    }

    // MARK: Action Buttons

    @ViewBuilder
    private var actionSection: some View {
        switch bt.transferState {
        case .idle:
            sendButton(label: "Send to CrossPoint", icon: "arrow.up.circle.fill") {
                startSend()
            }

        case .cancelled, .error:
            VStack(spacing: 12) {
                sendButton(label: "Try Again", icon: "arrow.clockwise.circle.fill") {
                    bt.reset()
                    startSend()
                }
                Button("Cancel") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

        case .scanning, .connecting, .preparing, .transferring:
            Button {
                bt.cancel()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemFill))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

        case .done:
            Button { dismiss() } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

        case .bluetoothUnavailable:
            Button { dismiss() } label: {
                Text("Close")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemFill))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func sendButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.airBookAccent)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func startSend() {
        guard let data = try? store.fileData(for: book) else {
            bt.transferState = .error("Could not read the book file.")
            return
        }
        bt.sendBook(name: book.filename, data: data)
    }
}

// MARK: - Transfer Status Area

struct TransferStatusArea: View {
    let state: TransferState
    let progress: Double
    let transferred: Int
    let total: Int

    var body: some View {
        VStack(spacing: 16) {
            stateIcon
                .frame(height: 88)

            Text(state.statusMessage)
                .font(.subheadline)
                .foregroundStyle(messageColor)
                .multilineTextAlignment(.center)
                .animation(.none, value: state)

            if case .transferring = state {
                VStack(spacing: 6) {
                    ProgressView(value: max(0, min(1, progress)))
                        .progressViewStyle(.linear)
                        .tint(Color.airBookAccent)
                        .scaleEffect(y: 1.4)

                    HStack {
                        Text(formatBytes(transferred))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.airBookAccent)
                        Spacer()
                        Text(formatBytes(total))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 46))
                .foregroundStyle(Color.airBookAccent.opacity(0.45))

        case .scanning:
            PulsingBluetoothView()

        case .connecting, .preparing:
            ProgressView()
                .scaleEffect(1.8)
                .tint(Color.airBookAccent)

        case .transferring:
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.airBookAccent)
                .symbolEffect(.bounce, options: .speed(0.5).repeating)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.green)

        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 50))
                .foregroundStyle(Color.secondary)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.orange)

        case .bluetoothUnavailable:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.secondary)
        }
    }

    private var messageColor: Color {
        switch state {
        case .done:                  return .green
        case .error:                 return .orange
        case .bluetoothUnavailable,
             .cancelled:             return .secondary
        default:                     return .primary
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Pulsing Bluetooth Animation

struct PulsingBluetoothView: View {
    @State private var animating = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.airBookAccent.opacity(animating ? 0.0 : 0.35), lineWidth: 1.5)
                    .frame(
                        width: CGFloat(44 + i * 22),
                        height: CGFloat(44 + i * 22)
                    )
                    .scaleEffect(animating ? 1.2 : 0.8)
                    .animation(
                        .easeOut(duration: 1.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.38),
                        value: animating
                    )
            }
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.airBookAccent)
        }
        .onAppear { animating = true }
    }
}
