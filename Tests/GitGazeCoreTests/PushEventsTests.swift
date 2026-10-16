import Foundation
import Testing
import GitGazeCore

struct PushEventsTests {
    @Test func detectsSuccessfulPushNotFetchFailureOrChildCompletion() {
        var events = PushEvents()
        func receive(_ json: String) -> Bool { events.receive(Data(json.utf8)) }
        #expect(!receive(#"{"event":"cmd_name","sid":"a","name":"push"}"#))
        #expect(!receive(#"{"event":"cmd_name","sid":"b","name":"fetch"}"#))
        #expect(!receive(#"{"event":"exit","sid":"b","code":0}"#))
        #expect(!receive(#"{"event":"exit","sid":"a/child","code":0}"#))
        #expect(receive(#"{"event":"exit","sid":"a","code":0}"#))
        #expect(!receive(#"{"event":"exit","sid":"a","code":0}"#))
        #expect(!receive(#"{"event":"cmd_name","sid":"c","name":"push"}"#))
        #expect(!receive(#"{"event":"exit","sid":"c","code":128}"#))
        #expect(!receive(#"{"event":"cmd_name","sid":"d","name":"push"}"#))
        #expect(!receive(#"{"event":"signal","sid":"d","signo":15}"#))
        #expect(!receive(#"{"event":"exit","sid":"d","code":0}"#))
        #expect(!receive("not json"))
    }
}
