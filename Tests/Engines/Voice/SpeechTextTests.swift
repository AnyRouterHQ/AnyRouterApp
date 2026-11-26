import Testing
@testable import AnyRouter

struct SpeechTextTests {
    @Test func markupIsRemovedAndLinkTextStays() {
        #expect(SpeechText.clean("**Bold** and [a link](https://example.com) here.") == "Bold and a link here.")
        #expect(SpeechText.clean("Use `git status` now") == "Use git status now")
        #expect(SpeechText.clean("See https://example.com/x now") == "See now")
        #expect(SpeechText.clean("![chart](https://example.com/c.png)Done") == "Done")
    }

    @Test func headingsBulletsAndNumbersLoseTheirMarks() {
        #expect(SpeechText.clean("# Title\n\n- one\n- two") == "Title\n\none\ntwo")
        #expect(SpeechText.clean("1. First\n2. Second") == "First\nSecond")
        #expect(SpeechText.clean("> quoted") == "quoted")
        #expect(SpeechText.clean("a\n---\nb") == "a\n\nb")
    }

    @Test func aReplyThatIsStillStreamingNeverShowsHalfALinkOrCodeBlock() {
        #expect(SpeechText.clean("Intro\n```py\nx = 1") == "Intro\n")
        #expect(SpeechText.clean("Read [the guide](https://exa") == "Read the guide")
        #expect(SpeechText.clean("Read [the gu") == "Read the gu")
    }

    @Test func tablePipesBecomePauses() {
        #expect(SpeechText.clean("a | b") == "a , b")
    }
}
