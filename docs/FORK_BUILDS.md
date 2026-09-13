# Fork builds and launcher releases

The **Windows installer** GitHub Actions workflow builds a fresh Windows x64 MSI
on each branch push, pull request to main, or manual run. Download the
`TpF2Multiplayer-<version>-<commit>` artifact from the completed run. It contains
`TpF2Multiplayer.msi`, `SHA256SUMS.txt` and `build-info.json`.

Ordinary builds are not launcher releases. They run with read-only repository
permissions. Only an intentional `vX.Y.Z` tag push in `tearded/tpf2-multiplayer`
enables the separate release job with permission to publish assets.

## Publishing a launcher version

1. Commit the complete intended changes. Uncommitted local files are not built.
2. Set the same three-part version in `installer/VERSION` and `LOBBY_VERSION` in
   `netpunch/lobby.py`. Use a new version higher than the previous fork release.
3. Add `docs/releases/X.Y.Z.md` with changes, actual validation and known issues.
4. Push the commit, then push its matching `vX.Y.Z` tag to the fork.

The workflow runs Lua/regression/relay checks, builds all binaries and the frozen
lobby, then creates an MSI using WiX 7.0.0. If the optional preview plugin is part
of the committed source, its native and Lua integration are required together,
its available regression tests run, and the DLL is included in the MSI.

An administrative extraction checks MSI identity/version and every payload file
against the build inputs. This does not install or run the game. Game testing
remains a separate release criterion and must not be implied by a green build.

For a version tag the package is uploaded to a draft release first. GitHub's asset
digest and a fresh download must match before the draft becomes the latest public
release. The public latest-release endpoint is then checked again. Existing
releases and assets are never overwritten; failed drafts remain for inspection.
The launcher follows this verified public endpoint and only accepts stable
three-part releases with `TpF2Multiplayer.msi` and a SHA-256 asset digest.

Both players select **Mein Fork** and the same version in the release launcher.
No per-update EXE needs to be sent. This workflow does not alter the separate
legacy private `tearded/TPF2-MP` / `mp-updates` channel.

Build dependencies and Actions revisions are pinned. The workflow accepts the
WiX 7 OSMF EULA for CI using the same explicit option as the local build script.
See [WiX OSMF](https://wixtoolset.org/osmf/). The VS toolchain is located through
vswhere, supporting both local Build Tools and GitHub's hosted Enterprise image.
