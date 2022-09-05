defmodule ExAudit.Adapters.DiffAdapter do
  @moduledoc ~S"""
  Defines the behaviour for a diff adapter.
  """

  @doc """
  Return the diff between two terms.
  """
  @callback diff(term, term) :: :map | ExAudit.Adapters.ErlangBinary.Diff.changes()

  @doc """
  Invert the diff between two terms.
  """
  @callback reverse(term) :: :map | ExAudit.Adapters.ErlangBinary.Diff.changes()

  @doc """
  Applies the patch to the given term
  """
  @callback patch(term, term) :: any()
end
