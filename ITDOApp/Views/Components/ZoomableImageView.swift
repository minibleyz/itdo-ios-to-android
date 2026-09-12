import SwiftUI

/// Полноэкранный просмотрщик изображений с pinch-to-zoom и двойным тапом.
/// Открывается по тапу на любое фото в ленте, чате или профиле.
struct ZoomableImageView: View {
    let urlString: String?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let urlString, let url = URL.secure(urlString) {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { value in
                                        lastScale = scale
                                        if scale < 1 {
                                            withAnimation(.spring()) {
                                                scale = 1; lastScale = 1
                                                offset = .zero; lastOffset = .zero
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if scale > 1 {
                                        scale = 1; lastScale = 1
                                        offset = .zero; lastOffset = .zero
                                    } else {
                                        scale = 2.5; lastScale = 2.5
                                    }
                                }
                            }
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .padding(16)
        }
        .statusBarHidden(true)
    }
}
