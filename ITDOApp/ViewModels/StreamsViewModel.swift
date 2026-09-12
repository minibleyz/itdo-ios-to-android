import Foundation

@MainActor
final class StreamsViewModel: ObservableObject {
    @Published var streams: [LiveStream] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: StreamListResponse = try await APIClient.shared.request("streams/list.php")
            streams = response.streams
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
