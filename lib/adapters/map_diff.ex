defmodule ExAudit.Adapters.MapDiff do
  @behaviour ExAudit.Adapters.DiffAdapter

  @undefined :"$undefined"

  @doc """
  Creates a patch that can be used to go from a to b with the ExAudit.Patch.patch function
  """
  def diff(a, b)

  def diff(a, a) do
    :not_changed
  end

  def diff(%{__struct__: a_struct} = a, %{__struct__: b_struct} = b) do
    if primitive_struct?(a_struct) and primitive_struct?(b_struct) do
      %{changed: :primitive_change, added: b, removed: a}
    else
      diff(Map.from_struct(a), Map.from_struct(b))
    end
  end

  def diff(%{} = a, %{} = b) do
    all_keys =
      (Map.keys(a) ++ Map.keys(b))
      |> Enum.uniq()

    changes =
      Enum.map(all_keys, fn key ->
        value_a = Map.get(a, key, @undefined)
        value_b = Map.get(b, key, @undefined)

        case {value_a, value_b} do
          {a, a} ->
            nil

          {@undefined, b} ->
            {key, Map.new(added: b)}

          {a, @undefined} ->
            {key, Map.new(removed: a)}

          {a, b} ->
            {key, Map.new(changed: diff(a, b))}
        end
      end)
      |> Enum.reject(&is_nil/1)

    case length(changes) do
      0 -> :not_changed
      _ -> Enum.into(changes, %{})
    end
  end

  def diff(a, b) when is_list(a) and is_list(b) do
    indexes = 0..:erlang.max(length(a) - 1, length(b) - 1)

    changes =
      for i <- indexes, into: [] do
        value_a = Enum.at(a, i, @undefined)
        value_b = Enum.at(b, i, @undefined)

        case {value_a, value_b} do
          {a, a} ->
            nil

          {@undefined, b} ->
            %{changed: :added_to_list, added: b, index: i}

          {a, @undefined} ->
            %{changed: :removed_from_list, removed: a, index: i}

          {a, b} ->
            %{changed: :changed_in_list, changes: diff(a, b), index: i}
        end
      end

    changes = Enum.reject(changes, &is_nil/1)

    case length(changes) do
      0 -> :not_changed
      _ -> changes
    end
  end

  def diff(a, b) do
    %{changed: :primitive_change, added: b, removed: a}
  end

  @doc """
  Reverts a patch so that it can undo a change
  """
  def reverse(:not_changed), do: :not_changed

  def reverse(%{changed: :primitive_change, removed: a, added: b}),
    do: %{changed: :primitive_change, removed: b, added: a}

  def reverse(%{added: a}), do: %{removed: a}

  def reverse(%{changed: :added, added: a}), do: %{changed: :removed, removed: a}

  def reverse(%{removed: a}), do: %{added: a}

  def reverse(%{changed: :removed, removed: a}), do: %{changed: :added, added: a}

  def reverse(%{changed: :changed, changes: changes}),
    do: %{changed: :changed, changes: reverse(changes)}

  def reverse(%{changed: :changed_in_list, index: index, changes: changes}),
    do: %{changed: :changed_in_list, index: index, changes: reverse(changes)}

  def reverse(changes) when is_map(changes) do
    changes
    |> Enum.map(fn {key, change} -> {key, reverse(change)} end)
    |> Enum.into(%{})
  end

  def reverse(changes) when is_list(changes) do
    changes
    |> Enum.reverse()
    |> Enum.map(&reverse/1)
  end

  @doc """
  Applies the patch to the given term
  """
  def patch(_, %{changed: :primitive_change, added: b, removed: _a}) do
    b
  end

  def patch(a, :not_changed) do
    a
  end

  def patch(list, changes) when is_list(list) and is_list(changes) do
    changes
    |> Enum.reverse()
    |> Enum.reduce(list, fn
      %{added: el}, map ->
        List.insert_at(map, -1, el)

      %{removed: el}, map ->
        List.delete(map, el)

      %{changed: :added_to_list, index: i, added: el}, list ->
        List.insert_at(list, i, el)

      %{changed: :removed_from_list, index: i, removed: _}, list ->
        List.delete_at(list, i)

      %{changed: :changed_in_list, index: i, changes: change}, list ->
        List.update_at(list, i, &patch(&1, change))
    end)
  end

  def patch(map, changes) when is_map(map) and is_map(changes) do
    changes
    |> Enum.reduce(map, fn
      {key, %{added: b}}, map ->
        Map.put(map, key, b)

      {key, %{changed: :added, added: b}}, map ->
        Map.put(map, key, b)

      {key, %{removed: _}}, map ->
        Map.delete(map, key)

      {key, %{changed: :removed, removed: _}}, map ->
        Map.delete(map, key)

      {key, %{changed: changes}}, map ->
        Map.update!(map, key, &patch(&1, changes))
    end)
  end

  ## PRIVATE

  defp primitive_struct?(type) do
    primitive_structs = Application.get_env(:ex_audit, :primitive_structs, [])

    type in primitive_structs
  end
end
