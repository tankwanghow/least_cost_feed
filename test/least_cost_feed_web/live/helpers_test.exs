defmodule LeastCostFeedWeb.HelpersTest do
  use ExUnit.Case, async: true
  alias LeastCostFeedWeb.Helpers

  # Expected strings were captured from Number.Delimit.number_to_delimited/2
  # (number 1.0.5) before that dependency was dropped.
  describe "number_delimited/2" do
    test "delimits thousands and defaults to 2 decimals" do
      assert Helpers.number_delimited(1_234_567.891) == "1,234,567.89"
      assert Helpers.number_delimited(123_456_789_012.0) == "123,456,789,012.00"
    end

    test "pads to the requested precision" do
      assert Helpers.number_delimited(1_234_567.891, precision: 4) == "1,234,567.8910"
      assert Helpers.number_delimited(0.5) == "0.50"
    end

    test "formats integers and zero" do
      assert Helpers.number_delimited(1000) == "1,000.00"
      assert Helpers.number_delimited(12) == "12.00"
      assert Helpers.number_delimited(0) == "0.00"
      assert Helpers.number_delimited(0.0) == "0.00"
    end

    test "rounds half up on the shortest float representation" do
      assert Helpers.number_delimited(999.995) == "1,000.00"
      assert Helpers.number_delimited(1.005) == "1.01"
    end

    test "keeps the sign of negatives, including ones that round to zero" do
      assert Helpers.number_delimited(-1234.5) == "-1,234.50"
      assert Helpers.number_delimited(-0.004) == "-0.00"
    end

    test "accepts Decimal and numeric strings" do
      assert Helpers.number_delimited(Decimal.new("9876.54321")) == "9,876.54"
      assert Helpers.number_delimited(Decimal.new("1234567.8"), precision: 4) == "1,234,567.8000"
      assert Helpers.number_delimited("1234.5") == "1,234.50"
    end

    test "passes nil through" do
      assert Helpers.number_delimited(nil) == nil
    end
  end

  # Expected strings follow Timex.from_now/1 (timex 3.7.13), which this replaced:
  # 30-day months, 360-day years, "yesterday"/"tomorrow" for the 1-2 day band.
  describe "relative_time/2" do
    @now ~U[2026-10-07 12:00:00Z]

    defp ago(seconds), do: Helpers.relative_time(DateTime.add(@now, -seconds), @now)

    test "seconds" do
      assert ago(0) == "now"
      assert ago(1) == "1 second ago"
      assert ago(30) == "30 seconds ago"
      assert ago(45) == "45 seconds ago"
    end

    test "minutes" do
      assert ago(46) == "1 minute ago"
      assert ago(119) == "1 minute ago"
      assert ago(120) == "2 minutes ago"
      assert ago(44 * 60) == "44 minutes ago"
      assert ago(3599) == "59 minutes ago"
    end

    test "hours and yesterday" do
      assert ago(3600) == "1 hour ago"
      assert ago(89 * 60) == "1 hour ago"
      assert ago(7200) == "2 hours ago"
      assert ago(22 * 3600) == "22 hours ago"
      assert ago(86_400) == "yesterday"
      assert ago(36 * 3600) == "yesterday"
    end

    test "days, months, years" do
      day = 86_400
      assert ago(2 * day) == "2 days ago"
      assert ago(26 * day) == "26 days ago"
      assert ago(30 * day) == "1 month ago"
      assert ago(45 * day) == "1 month ago"
      assert ago(60 * day) == "2 months ago"
      assert ago(320 * day) == "10 months ago"
      assert ago(360 * day) == "1 year ago"
      assert ago(548 * day) == "1 year ago"
      assert ago(800 * day) == "2 years ago"
    end

    test "future times" do
      assert ago(-30) == "in 30 seconds"
      assert ago(-60) == "in 1 minute"
      assert ago(-3600) == "in 1 hour"
      assert ago(-86_400) == "tomorrow"
      assert ago(-5 * 86_400) == "in 5 days"
    end

    test "accepts NaiveDateTime as UTC" do
      assert Helpers.relative_time(~N[2026-10-07 11:58:00], @now) == "2 minutes ago"
    end
  end

  describe "parse_csv_datetime/1" do
    test "parses Postgres text timestamps to a whole-second UTC DateTime" do
      assert Helpers.parse_csv_datetime("2024-05-01 12:34:56.123456") == ~U[2024-05-01 12:34:56Z]
      assert Helpers.parse_csv_datetime("2024-05-01 12:34:56.5") == ~U[2024-05-01 12:34:56Z]
    end
  end
end
