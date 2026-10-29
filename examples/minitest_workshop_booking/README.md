# Workshop booking (Minitest)

This example models workshop capacity and waitlisting in a Minitest project. It
contains several easy-to-miss boundaries: zero-seat requests, exact remaining
capacity, and the maximum waitlist request.

```sh
bundle install
bundle exec ruby test/strong/registration_test.rb
bundle exec moots
```

The default configuration uses two isolated mutation workers and expects every
mutation to be killed.

The weak suite looks reasonable and passes, but omits exact boundary and disabled-
waitlist behavior:

```sh
bundle exec ruby test/weak/registration_test.rb
bundle exec moots --config .moots.weak.yml
```

Moots exits `1` and identifies the rules that those tests do not distinguish.
