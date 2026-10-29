# frozen_string_literal: true

module WorkshopBooking
  # Decides whether a seat request is confirmed, waitlisted or declined.
  class Registration
    WAITLIST_LIMIT = 2

    def initialize(capacity:, booked:, waitlist_enabled:)
      @capacity = capacity
      @booked = booked
      @waitlist_enabled = waitlist_enabled
    end

    def status(requested_seats:)
      return :invalid if requested_seats <= 0

      remaining = capacity - booked
      return :confirmed if requested_seats <= remaining
      return :waitlisted if waitlist_enabled && requested_seats <= WAITLIST_LIMIT

      :declined
    end

    def projected_booked(requested_seats:)
      booked + requested_seats
    end

    private

    attr_reader :capacity, :booked, :waitlist_enabled
  end
end
