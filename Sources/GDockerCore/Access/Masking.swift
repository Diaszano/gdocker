import Foundation

public enum Masking {
    /// Replaces every value in `Config.Env` with `***`. Fails closed: input that is not a JSON object is withheld
    /// rather than passed through, so a secret can never leak just because parsing failed.
    public static func maskEnv(inInspectJSON json: String) -> String {
        guard var object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            return #"{"error":"inspect output withheld: could not be parsed to mask secrets"}"#
        }
        if var config = object["Config"] as? [String: Any], let env = config["Env"] as? [String] {
            config["Env"] = env.map { entry in
                guard let equals = entry.firstIndex(of: "=") else { return entry }
                return String(entry[..<equals]) + "=***"
            }
            object["Config"] = config
        }
        let data =
            (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
