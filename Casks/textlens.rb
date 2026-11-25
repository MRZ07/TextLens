cask "textlens" do
  version "0.2.1"
  sha256 "5e3c9c30205a87cb455968faed749b5a946dff7c77530121d016453b60dbaaee"

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
