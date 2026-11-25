cask "textlens" do
  version "0.2.0"
  sha256 "f642a03482e09c6066d993349991cafd883c4249f609837d83d4993325ecc823"

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
