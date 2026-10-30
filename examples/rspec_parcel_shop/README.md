# Parcel shop (RSpec)

This small parcel-pricing service demonstrates Moots in an RSpec project. The
production code contains free-delivery, parcel-weight and express-delivery
boundaries that deserve exact tests.

```sh
bundle install
bundle exec rspec spec/strong
bundle exec moots
```

The default configuration uses the strong suite and exits successfully only when
every mutation is killed. It runs two isolated mutation workers.

For comparison, run the deliberately plausible but incomplete suite:

```sh
bundle exec rspec spec/weak
bundle exec moots --config .moots.weak.yml
```

The weak tests pass, but Moots exits `1` and reports surviving boundary mutations.
That contrast is the point of the example: passing tests alone do not show that
the delivery rules are pinned down.
