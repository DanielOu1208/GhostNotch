import SwiftUI

struct IslandExpandedView: View {
    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                TerminalLine(prompt: "ghostnotch", command: "pwd")
                Text("/Users/danielou")
                    .foregroundStyle(.white.opacity(0.52))

                TerminalLine(prompt: "ghostnotch", command: "git status")
                Text("Stage 1 placeholder terminal")
                    .foregroundStyle(.green.opacity(0.78))

                HStack(spacing: 0) {
                    Text("ghostnotch")
                        .foregroundStyle(.cyan.opacity(0.82))
                    Text(" % ")
                        .foregroundStyle(.white.opacity(0.55))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 7, height: 15)
                }
            }
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.45), radius: 5)

            Text("GhostNotch")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text("placeholder")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))

            Spacer()

            Text("Esc")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }
}

private struct TerminalLine: View {
    let prompt: String
    let command: String

    var body: some View {
        HStack(spacing: 0) {
            Text(prompt)
                .foregroundStyle(.cyan.opacity(0.82))
            Text(" % ")
                .foregroundStyle(.white.opacity(0.55))
            Text(command)
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}
