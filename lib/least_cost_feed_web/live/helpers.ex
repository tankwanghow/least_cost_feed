defmodule LeastCostFeedWeb.Helpers do
  def delete_line(cs, id, lines_name, id_field) do
    existing = Ecto.Changeset.get_assoc(cs, lines_name)

    index =
      Enum.find_index(existing, fn x ->
        Ecto.Changeset.get_field(x, id_field) == String.to_integer(id)
      end)

    {to_delete, rest} = List.pop_at(existing, index)

    lines =
      if Ecto.Changeset.change(to_delete).data.id do
        List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
      else
        rest
      end

    cs |> Ecto.Changeset.put_assoc(lines_name, lines)
  end

  def add_line(cs, lines_name, params) do
    existing = Ecto.Changeset.get_assoc(cs, lines_name)
    Ecto.Changeset.put_assoc(cs, lines_name, existing ++ [params])
  end

  use LeastCostFeedWeb, :live_view
  import Ecto.Query, warn: false

  def sort(socket, sort_by, query, empty_sort_directions) do
    order_params =
      if socket.assigns.sort_directions[sort_by] == :asc do
        [desc: String.to_atom(sort_by)]
      else
        [asc: String.to_atom(sort_by)]
      end

    {direction, _} = Enum.at(order_params, 0)

    socket
    |> assign(
      sort_directions:
        socket.assigns.sort_directions
        |> Map.merge(empty_sort_directions)
        |> Map.merge(%{sort_by => direction})
    )
    |> assign(query: query.(socket) |> order_by(^order_params))
  end

  def float_parse(nil), do: nil
  def float_parse(""), do: nil

  def float_parse(value) do
    {v, t} = if is_number(value), do: {value, ""}, else: Float.parse("0" <> value)
    if t != "", do: :error, else: v
  end

  def float_decimal(value, decimal \\ 4)
  def float_decimal(nil, _), do: nil
  def float_decimal("", _), do: nil

  def float_decimal(value, decimal) do
    float = float_parse(value)
    :erlang.float_to_binary(float, [:compact, decimals: decimal])
  end
end
