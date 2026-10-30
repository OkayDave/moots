# Moots example projects

These are standalone consumer projects that install Moots 0.1.0 from RubyGems.
They do not use the repository checkout as a path dependency.

| Project | Test framework | Domain | Strong result | Weak result |
| --- | --- | --- | --- | --- |
| [`rspec_parcel_shop`](rspec_parcel_shop) | RSpec | Parcel and delivery pricing | 7/7 killed | 4 killed, 3 survived |
| [`minitest_workshop_booking`](minitest_workshop_booking) | Minitest | Capacity and waitlisting | 6/6 killed | 2 killed, 4 survived |

Each project has its own Gemfile, lockfile, Moots configurations, source, tests
and instructions. The strong suite covers exact decision boundaries. The weak
suite is intentionally realistic rather than obviously empty: it passes, but
does not distinguish several mutations.

To reproduce the complete check used by this repository's Examples workflow:

```sh
cd examples/rspec_parcel_shop
bundle install
bundle exec ruby ../verify.rb
```

Repeat from `minitest_workshop_booking` for the Minitest example. The verifier
expects the strong run to exit `0` with no survivors and the weak run to exit `1`
with a mixture of killed and surviving mutations.
