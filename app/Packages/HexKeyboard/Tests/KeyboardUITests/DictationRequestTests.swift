import Foundation
import Testing
import KeyboardUI

@MainActor
struct DictationRequestTests {
    @Test func theLinkCarriesTheAppToGoBackTo() {
        let request = Dictation.Request(host: "ph.telegra.Telegraph")
        #expect(request.url.absoluteString == "hexkeyboard://dictate?host=ph.telegra.Telegraph")
        #expect(Dictation.Request(request.url) == request)
    }

    @Test func aLinkWithoutAnAppStillDictates() {
        #expect(Dictation.Request(host: nil).url.absoluteString == "hexkeyboard://dictate")
        #expect(Dictation.Request(URL(string: "hexkeyboard://dictate")!) == Dictation.Request(host: nil))
    }

    @Test func otherLinksAreNotRequests() {
        #expect(Dictation.Request(URL(string: "hexkeyboard://source?url=x")!) == nil)
        #expect(Dictation.Request(URL(string: "tg://dictate")!) == nil)
    }
}
