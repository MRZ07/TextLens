import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureText = Self(
        "captureText",
        initial: .init(.t, modifiers: [.command, .option, .shift])
    )

    static let captureTextWithoutLineBreaks = Self(
        "captureTextWithoutLineBreaks",
        initial: .init(.l, modifiers: [.command, .option, .shift])
    )
}
