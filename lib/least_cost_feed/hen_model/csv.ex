defmodule LeastCostFeed.HenModel.CSV do
  @moduledoc """
  Tiny CSV loader for the `priv/hen_model/*.csv` data files.

  Lines starting with `#` (comments) are skipped, the first remaining line is
  the header, and each row becomes a map keyed by header string.
  """

  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

  @doc "Absolute path of a data file in `priv/hen_model/` (source tree, for compile-time loading)."
  def path(file),
    do: Path.join([__DIR__, "..", "..", "..", "priv", "hen_model", file]) |> Path.expand()

  @doc "Reads a CSV file into a list of maps."
  def read!(file) do
    lines =
      file
      |> path()
      |> File.read!()
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
      |> Enum.join("\n")

    [header | rows] = __MODULE__.Parser.parse_string(lines <> "\n", skip_headers: false)

    Enum.map(rows, fn row -> header |> Enum.zip(row) |> Map.new() end)
  end

  @doc "Parses a float, returning nil for blanks or non-numeric text."
  def to_float(nil), do: nil

  def to_float(str) when is_binary(str) do
    case Float.parse(String.trim(str)) do
      {f, ""} -> f
      _ -> nil
    end
  end
end
