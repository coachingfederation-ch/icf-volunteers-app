import Foundation

/// Central configuration for the wrapper. Keep everything in one place.
enum Config {
    /// The web view's landing page. This is the QR/email sign-in flow the
    /// volunteers already know.
    static let webAppURL = "https://new.coachingfederation.ch/volunteer-chat"

    /// Authenticated endpoint the background-refresh poller hits to ask
    /// "is there a chat waiting to be accepted by me?".
    /// Implemented by the Lovable backend prompt (see docs/).
    static let waitingChatCheckURL = "https://new.coachingfederation.ch/api/volunteer-chat/waiting"

    /// Supabase project URL + anon key for the background poller. These are
    /// public (they ship in the web app), so they are safe to embed here.
    /// Fill in from the Lovable/Supabase project settings.
    static let supabaseURL = "https://dhmzxwtsigbcrlfcxudh.supabase.co"
    static let supabaseAnonKey = "sb_publishable_u4Nw1UpAnG7hm2ke4FEWZQ_qN8eVLtf"

    /// Bundle identifier — also the `apns-topic` header value for APNs pushes.
    static let bundleID = "ch.coachingfederation.icf.volunteers"
}
