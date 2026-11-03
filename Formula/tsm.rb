class Tsm < Formula
  desc "Run several Tailscale tailnets on one Mac at the same time, one daemon per tailnet"
  homepage "https://github.com/igorsigalovs/tailscale-multi"
  url "https://github.com/igorsigalovs/tailscale-multi/releases/download/v0.1.0/tsm-0.1.0.tar.gz"
  sha256 "bf428651336bf209198497ca6afeb88c9f6cde966793a614653b7a143742582e"
  license "MIT"
  head "https://github.com/igorsigalovs/tailscale-multi.git", branch: "main"

  depends_on :macos
  depends_on "python@3.12"
  depends_on "tailscale"

  def install
    bin.install "bin/tsm"
  end

  def caveats
    <<~EOS
      tsm replaces the Tailscale GUI app; quit/uninstall it before `tsm add`.
      Each tailnet becomes a root launchd service, so `tsm add` will ask for sudo.

        tsm add home                   # Tailscale SaaS, opens a browser login
        tsm add work --login-server https://headscale.example.com
        tsm list

      Remove everything with `tsm uninstall`.
    EOS
  end

  test do
    assert_match "tsm #{version}", shell_output("#{bin}/tsm version")
    assert_match "tsm add", shell_output("#{bin}/tsm --help")
  end
end
