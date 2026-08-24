import Foundation

/// Background poller: asks Supabase directly whether any live-chat
/// conversation is waiting to be accepted. The stored Supabase access token
/// (handed over by the web app via the `authState` bridge message) is a valid
/// JWT, and RLS lets an authenticated volunteer read `status = 'waiting'`
/// rows. So we need no custom backend endpoint.
struct ChatStatusPoller {
    static func checkForWaitingChat(completion: @escaping (Bool) -> Void) {
        guard let token = TokenStore.load(),
              Config.supabaseURL.contains("YOUR-PROJECT") == false,
              Config.supabaseAnonKey.contains("YOUR-SUPABASE") == false,
              var url = URL(string: Config.supabaseURL + "/rest/v1/live_chat_conversations")
        else {
            completion(false)
            return
        }

        url.append(queryItems: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "status", value: "eq.waiting"),
            URLQueryItem(name: "limit", value: "1"),
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(false)
                return
            }
            // A non-empty array means at least one chat is waiting.
            let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            completion(!(rows ?? []).isEmpty)
        }.resume()
    }
}
