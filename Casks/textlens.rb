cask "textlens" do
  version "0.1.0"
  sha256 "e5b2913783b0e1385bde0062599834b4d4caec8ab09c4bcbd10b84dd2c80478e"

  url "https://github.com/MRZ07/TextLens/releases/download/v#{version}/TextLens-#{version}.zip"
  name "TextLens"
  desc "Copy on-screen text with local OCR"
  homepage "https://github.com/MRZ07/TextLens"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "TextLens.app"

  uninstall quit: "com.textlens.app"

  zap trash: [
    "~/Library/Application Support/TextLens",
    "~/Library/Preferences/com.textlens.app.plist",
    "~/Library/Saved Application State/com.textlens.app.savedState",
  ]
end
