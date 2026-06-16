import SwiftUI

// MARK: - Book Status Badge
//
// Compact icon (+ optional percentage during upload) shown under each grid
// card. The variant on `BookLibraryStatus` decides icon, color, and whether
// to render a progress percentage.

struct BookStatusBadge: View {
    let status: BookLibraryStatus
    var iconSize: CGFloat = 9

    var body: some View {
        switch status {
        case .uploading(let p):
            HStack(spacing: 3) {
                CircularMicroProgress(value: p)
                    .frame(width: iconSize + 2, height: iconSize + 2)
                Text("\(Int((max(0, min(1, p))) * 100))%")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.paperInk)
                    .monospacedDigit()
            }
        case .syncedFull:
            icon("icloud.fill", weight: .light, color: .paperInk)
        case .syncedEntryOnly:
            icon("icloud", weight: .light, color: .paperRule)
        case .notOnDevice:
            icon("icloud.slash", weight: .light, color: .paperRule)
        case .queuedForUpload:
            icon("arrow.up.circle", weight: .light, color: .paperRule)
        case .queuedForFileRemoval:
            icon("tray.and.arrow.down", weight: .light, color: .paperRule)
        case .queuedForEntryDeletion:
            icon("minus.circle", weight: .light, color: .paperError)
        case .foreign:
            icon("questionmark.circle", weight: .light, color: .paperRule)
        case .failed:
            icon("exclamationmark.triangle.fill", weight: .light, color: .paperError)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func icon(_ name: String, weight: Font.Weight, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: iconSize, weight: weight))
            .foregroundStyle(color)
    }
}

// MARK: - Micro circular progress
//
// 10-pt determinate ring used inside BookStatusBadge during uploads. Doesn't
// rely on ProgressView so it can match the paper aesthetic exactly.

struct CircularMicroProgress: View {
    let value: Double

    var body: some View {
        let clamped = max(0, min(1, value))
        ZStack {
            Circle()
                .stroke(Color.paperRule.opacity(0.28), lineWidth: 1)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(Color.paperInk,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
