import Foundation

enum SupabaseConfig {
    static var url: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), !raw.isEmpty, !raw.contains("placeholder") else {
            fatalError("SUPABASE_URL is missing. Set Config/Secrets.xcconfig or CI secrets.")
        }
        return url
    }

    static var anonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.contains("placeholder") else {
            fatalError("SUPABASE_ANON_KEY is missing. Set Config/Secrets.xcconfig or CI secrets.")
        }
        return key
    }

    static var isConfigured: Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            return false
        }
        return !raw.isEmpty && !key.isEmpty && !raw.contains("placeholder") && !key.contains("placeholder")
    }
}
