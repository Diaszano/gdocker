import Foundation
import Testing
@testable import GDockerCore

private func object(_ json: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

@Test func maskEnvMasksValuesAndKeepsTheRest() throws {
    let raw = #"{"Image":"x","Config":{"Env":["A=secret","B=x=y","NOEQ"],"Tty":false}}"#
    let masked = try object(Masking.maskEnv(inInspectJSON: raw))
    let config = try #require(masked["Config"] as? [String: Any])
    #expect(config["Env"] as? [String] == ["A=***", "B=***", "NOEQ"])
    #expect(config["Tty"] as? Bool == false)
    #expect(masked["Image"] as? String == "x")
}

@Test func maskEnvWithoutEnvIsUnchanged() throws {
    let masked = try object(Masking.maskEnv(inInspectJSON: #"{"Image":"x","Config":{"Tty":true}}"#))
    #expect(masked["Image"] as? String == "x")
    #expect((masked["Config"] as? [String: Any])?["Env"] == nil)
}

@Test func unparseableInputIsWithheldNotLeaked() {
    let out = Masking.maskEnv(inInspectJSON: "Env=SECRET=hunter2 not json")
    #expect(!out.contains("hunter2"))
}
