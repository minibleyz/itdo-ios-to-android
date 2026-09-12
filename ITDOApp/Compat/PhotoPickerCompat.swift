import SwiftUI
import PhotosUI

// MARK: - iOS 15 совместимость для выбора фото
//
// PhotosPicker/PhotosPickerItem (SwiftUI, PhotosUI) появились в iOS 16.
// CompatPhotoPicker даёт то же самое (выбор изображений из галереи без
// запроса полного доступа к фото) на iOS 14+, используя UIKit'овский
// PHPickerViewController напрямую — он работает одинаково на всех версиях,
// поэтому отдельная ветка для iOS 16+ не нужна.
struct CompatPhotoPicker<Label: View>: View {
    /// Максимум изображений за один выбор (1 = одиночный выбор).
    let selectionLimit: Int
    /// Вызывается с уже загруженными данными выбранных изображений.
    let onPick: ([Data]) -> Void
    @ViewBuilder var label: () -> Label

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            label()
        }
        .sheet(isPresented: $showPicker) {
            PHPickerRepresentable(selectionLimit: selectionLimit, onPick: onPick)
        }
    }
}

private struct PHPickerRepresentable: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPick: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = selectionLimit
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([Data]) -> Void

        init(onPick: @escaping ([Data]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                onPick([])
                return
            }
            var datas: [Data?] = Array(repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        datas[index] = image.jpegData(compressionQuality: 0.9)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.onPick(datas.compactMap { $0 })
            }
        }
    }
}
