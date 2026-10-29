# Releasing Moots

Moots publishes through GitHub Actions and RubyGems trusted publishing. Do not
store a RubyGems API key in the repository or its GitHub secrets.

## One-time RubyGems setup

Create a pending trusted publisher in the RubyGems.org account that will own the
new `moots` gem. Use these exact values:

- Gem name: `moots`
- Repository owner: `OkayDave`
- Repository name: `moots`
- Workflow filename: `release.yml`
- Environment: `release`

After the first successful publication, RubyGems converts the pending publisher
to a normal trusted publisher and adds the account as an owner of the gem.

## Release process

1. Update `Moots::VERSION` and move the completed changes in `CHANGELOG.md` under
   a dated heading for that version.
2. Run `bundle exec rake verify` and `bundle exec rake build` locally.
3. Merge the release preparation to `main` and wait for the full Ruby matrix to
   pass.
4. From the GitHub Actions page, run the **Release gem** workflow against `main`.

The workflow builds and publishes the gem using a short-lived RubyGems credential,
creates and pushes the `vVERSION` tag, waits for RubyGems.org to serve the release,
and creates the matching GitHub release. It refuses to publish from any branch
other than `main`.

Afterward, verify the public artifact in a clean environment:

```sh
gem install moots -v VERSION
moots --version
```
