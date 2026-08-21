class PerfLab < Formula
  include Language::Python::Virtualenv

  desc "Local FPS / CPU / GPU / power profiler for iPhone and Android, with one-tap onboarding wizard"
  homepage "https://github.com/walkpod1007/3cdog-perf"
  url "https://github.com/walkpod1007/3cdog-perf/archive/refs/tags/v0.2.0.tar.gz"
  # sha256 of the v0.2.0 release tarball (verified at publish time).
  sha256 "3dc738d564b0dd8d71309fd4d037ad8660e1e9b89485d22110f21172dafc1340"
  version "0.2.0"
  revision 1

  # ``python@3.12`` is the floor chosen by the task brief for predictable
  # library compatibility. The 3cdog-perf package itself is stdlib-only, so
  # this only governs the venv interpreter.
  depends_on "python@3.12"

  # ``android-platform-tools`` is a Cask, not a Formula, so Homebrew cannot
  # pull it automatically from a Formula stanza. The in-app onboarding
  # wizard prints the install hint; we mirror the same wording here so users
  # who only read the brew output are not stranded.

  # iPhone support needs ``pymobiledevice3`` plus a transitive dependency
  # tree of ~20 wheels. Homebrew's virtualenv resource mechanism only
  # fetches the wheel you name and cannot recurse into PyPI metadata, so
  # pulling pymobiledevice3 from this formula would leave the sandbox venv
  # half-broken the first time the wizard tries to import it. Instead we
  # ship a clean Python venv (stdlib-only) and tell day-one iPhone users
  # to install pymobiledevice3 outside the formula via ``pipx``, which
  # keeps the dependency tree in user-space where PyPI resolution just
  # works. The server's onboarding wizard prints the same one-liner, so
  # users see identical guidance whether they read it in the brew caveats
  # or in the UI.

  def install
    # ``virtualenv_install_with_resources`` builds the in-tree wheel from
    # ``pyproject.toml`` (zero runtime deps — pure stdlib) and installs it
    # into ``libexec/Virtualenv`` using ``Formula["python@3.12"]``. There
    # are no resource blocks to fetch: the formula is intentionally
    # minimal so the sandbox install never needs PyPI access.
    virtualenv_install_with_resources
  end

  def caveats
    <<~EOS
      3cdog-perf is installed. Two side-channel tools are referenced by the
      in-app onboarding wizard but not auto-installed because they live in
      different Homebrew namespaces / require PyPI resolution that the brew
      sandbox cannot do for you:

        Android (adb):  brew install --cask android-platform-tools
        iPhone (tunneld):
                          brew install pipx && pipx ensurepath
                          # then in a fresh shell:
                          pipx install pymobiledevice3
                          # keep a separate terminal open with:
                          sudo pymobiledevice3 remote tunneld   (iOS 17+)

      Launch with:

        3cdog-perf

      The browser opens automatically. If it doesn't, copy
      http://127.0.0.1:8765 into your browser.
    EOS
  end

  test do
    # (1) Binary wires up. ``--version`` prints the package version banner.
    version_output = shell_output("#{bin}/3cdog-perf --version")
    assert_match(/3cdog-perf/, version_output)
    assert_match(/0\.2\.0/, version_output)

    # (2) Side-effect free startup probe. We launch the server bound to an
    # ephemeral port and confirm the onboarding endpoint answers with the
    # expected two-platform envelope. 8 second ceiling so a slow CI doesn't
    # hang here for minutes.
    #
    # ``curl`` may briefly fail with connection-refused while the server is
    # still binding the socket. We retry with an explicit cap (and only
    # treat repeated non-zero exits as a failure) so the test does not
    # flake on the first probe that races the listener.
    require "timeout"
    port = free_port
    pid = spawn(
      { "3CDOG_PERF_PORT" => port.to_s },
      bin/"3cdog-perf",
      "--no-open-browser",
      "--host", "127.0.0.1",
      "--port", port.to_s,
      out: testpath/"server.log",
      err: testpath/"server.log",
    )
    body = nil
    begin
      Timeout.timeout(8) do
        attempts = 0
        loop do
          attempts += 1
          output = `curl -fsS http://127.0.0.1:#{port}/api/onboarding/state 2>&1`
          if $?.success?
            body = output
            break
          end
          if attempts >= 20
            raise "onboarding endpoint never returned a 2xx after #{attempts} probes"
          end
          sleep 0.25
        end
      end
      parsed = JSON.parse(body)
      assert_kind_of Hash, parsed["android"]
      assert_kind_of Hash, parsed["ios"]
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
